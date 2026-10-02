//
//  ScreenCaptureManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI
import ScreenCaptureKit

struct CaptureRequestState {
    private(set) var activeID: UUID?
    private(set) var latestID: UUID?

    mutating func begin() -> UUID? {
        guard activeID == nil else { return nil }
        let id = UUID()
        activeID = id
        latestID = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool { activeID == id }
    func isLatest(_ id: UUID) -> Bool { latestID == id }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }
}

@MainActor
class ScreenCaptureManager: NSObject {

    struct CaptureGeometry {
        let sourceRect: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
    }

    static func captureGeometry(for rect: CGRect, scaleFactor: CGFloat) -> CaptureGeometry {
        CaptureGeometry(
            sourceRect: rect,
            pixelWidth: max(1, Int(rect.width * scaleFactor)),
            pixelHeight: max(1, Int(rect.height * scaleFactor))
        )
    }
    
    private var overlayWindows: [OverlayWindow] = []
    private var requestState = CaptureRequestState()
    
    struct CaptureSelection {
        let rect: CGRect
        let screen: NSScreen
        let mode: CaptureMode
    }

    private var selectedRegion: CaptureSelection?
    private var streamContent: SCShareableContent?
    private var previousApp: NSRunningApplication?
    var onCaptureComplete: ((CGImage?, NSScreen?, CaptureMode, UUID) -> Void)?
    var onPrewarmRequested: ((CaptureMode) -> Void)?
    var onSessionReset: (() -> Void)?

    func isLatestCapture(_ requestID: UUID) -> Bool {
        requestState.isLatest(requestID)
    }

    // MARK: - Lifecycle & Pre-warming
    
    /// Pre-warms ScreenCaptureKit and system privacy permissions in the background during app startup.
    func prewarm() {
        Task(priority: .background) {
            _ = try? await SCShareableContent.current
        }
    }

    // MARK: - UI Flow
    
    func startCapture() {
        guard let requestID = requestState.begin() else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        onSessionReset?()
        let initialMode = SettingsManager.shared.initialCaptureMode()
        if initialMode == SettingsManager.shared.defaultCaptureMode {
            onPrewarmRequested?(initialMode)
        }
        Task { await showOverlay(for: requestID) }
    }
    
    // MARK: - Animation & Transition Metrics
    private static let overlayFadeInDuration: TimeInterval = 0.2
    private static let overlayFadeInTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    private func showOverlay(for requestID: UUID) async {
        guard requestState.isCurrent(requestID), overlayWindows.isEmpty else { return }
        do {
            let content = try await SCShareableContent.current
            guard requestState.isCurrent(requestID) else { return }
            streamContent = content
        } catch {
            log("Permission Error: \(error.localizedDescription)", type: .error)
            complete(with: nil, for: requestID)
            return
        }
        let onCaptureAction: (CGRect, NSScreen, CaptureMode) -> Void = { [weak self] localRect, screen, mode in
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordMouseRelease()
            #endif
            Task { @MainActor in
                guard let self = self else { return }
                // The first gesture to end wins.
                if self.requestState.isCurrent(requestID), !self.overlayWindows.isEmpty {
                    self.selectedRegion = CaptureSelection(rect: localRect, screen: screen, mode: mode)
                    if localRect != .zero {
                        SettingsManager.shared.recordCaptureModeUsed(mode)
                    }
                    self.closeOverlay()
                    if localRect != .zero {
                        await self.captureSelection(for: requestID)
                    } else {
                        self.complete(with: nil, for: requestID)
                    }
                }
            }
        }

        // All displays share the selected mode while each keeps its own menu origin.
        let initialMode = SettingsManager.shared.initialCaptureMode()
        let modeSelection = CaptureModeSelection(mode: initialMode)
        modeSelection.onModeSelected = { [weak self] selectedMode in
            guard let self else { return }
            if selectedMode == .latex || selectedMode == .qrBarcode || selectedMode == .standardOCR || selectedMode == .table {
                self.onPrewarmRequested?(selectedMode)
            }
        }
        // Create one overlay window for each screen.
        for screen in NSScreen.screens {
            log("NSScreen Frame: \(screen.frame)")
            let modeInteraction = CaptureModeInteraction(selection: modeSelection)
            let captureView = CaptureView(onCapture: onCaptureAction, screen: screen,
                                          modeInteraction: modeInteraction)
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.sharingType = .none // Excludes overlay from ScreenCaptureKit recordings
            let hostingView = ActionHostingView(rootView: captureView)
            window.contentView = hostingView
            hostingView.onRightMouseDown = { point, size in modeInteraction.begin(at: point, in: size) }
            hostingView.onRightMouseDragged = { point in modeInteraction.move(to: point) }
            hostingView.onRightMouseUp = { point in modeInteraction.end(at: point) }
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.acceptsMouseMovedEvents = true
            window.alphaValue = 0.0 // Start at 0 for fade in
            window.onEscape = { [weak self] in Task { @MainActor in self?.cancelCapture(for: requestID) } }
            overlayWindows.append(window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        overlayWindows.first?.makeKey()
        NSCursor.hide()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.overlayFadeInDuration
            context.timingFunction = Self.overlayFadeInTimingFunction
            self.overlayWindows.forEach { $0.animator().alphaValue = 1.0 }
        }, completionHandler: nil)
    }

    private func closeOverlay() {
        let windowsToClose = self.overlayWindows
        self.overlayWindows = []
        windowsToClose.forEach { $0.orderOut(nil) }
        NSCursor.unhide()
        
        // Restore the previously active application to prevent greyed-out windows
        if let app = previousApp {
            app.activate(options: [])
        }
        previousApp = nil
    }
    
    private func cancelCapture(for requestID: UUID) {
        guard requestState.isCurrent(requestID) else { return }
        closeOverlay()
        complete(with: nil, for: requestID)
    }
    
    // MARK: - Capture Flow
    
    /// Captures the selected screen region instantly using macOS 14+ SCScreenshotManager.
    private func captureSelection(for requestID: UUID) async {
        guard requestState.isCurrent(requestID) else { return }
        guard let content = streamContent, let selection = selectedRegion else {
            log("Error: Missing shareable content or selection data.", type: .error)
            complete(with: nil, for: requestID)
            return
        }
        
        guard let targetDisplay = findMatchingDisplay(for: selection.screen, in: content) else {
            log("Error: Could not find matching SCDisplay for screen.", type: .error)
            complete(with: nil, for: requestID)
            return
        }
        
        let (filter, config) = makeCaptureConfiguration(display: targetDisplay, selection: selection)
        
        do {
            log("Capturing frame via SCScreenshotManager...")
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordCaptureAcquired()
            #endif
            log("Frame captured successfully (\(cgImage.width)x\(cgImage.height) px).")
            complete(with: cgImage, for: requestID)
        } catch {
            log("SCScreenshotManager capture failed: \(error.localizedDescription)", type: .error)
            complete(with: nil, for: requestID)
        }
    }
    
    // MARK: - Helpers
    
    private func findMatchingDisplay(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return content.displays.first(where: { $0.displayID == screenNumber })
    }
    
    private func makeCaptureConfiguration(display: SCDisplay, selection: CaptureSelection) -> (SCContentFilter, SCStreamConfiguration) {
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        let geometry = Self.captureGeometry(for: selection.rect, scaleFactor: selection.screen.backingScaleFactor)
        
        config.sourceRect = geometry.sourceRect
        config.width = geometry.pixelWidth
        config.height = geometry.pixelHeight
        config.scalesToFit = true
        config.showsCursor = false
        
        return (filter, config)
    }
    
    private func complete(with image: CGImage?, for requestID: UUID) {
        guard requestState.finish(requestID) else { return }
        
        streamContent = nil
        let activeScreen = selectedRegion?.screen
        let mode = selectedRegion?.mode ?? .standardOCR
        selectedRegion = nil
        
        log("Capture sequence completed. Success: \(image != nil)")
        onCaptureComplete?(image, activeScreen, mode, requestID)
    }

    // MARK: - Logging helper
    
    private enum LogType { case info, error }
    
    private func log(_ message: String, type: LogType = .info) {
        let prefix = type == .error ? "[ScreenCaptureManager] ❌" : "[ScreenCaptureManager] ℹ️"
        debugPrint("\(prefix) \(message)")
    }
}
