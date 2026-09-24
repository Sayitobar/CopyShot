//
//  ScreenCaptureManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI
import ScreenCaptureKit

@MainActor
class ScreenCaptureManager: NSObject {
    
    private var overlayWindows: [OverlayWindow] = []
    private var isCaptureActive = false
    
    struct CaptureSelection {
        let rect: CGRect
        let screen: NSScreen
    }

    private var selectedRegion: CaptureSelection?
    private var streamContent: SCShareableContent?
    private var previousApp: NSRunningApplication?
    var onCaptureComplete: ((CGImage?, NSScreen?) -> Void)?

    // MARK: - Lifecycle & Pre-warming
    
    /// Pre-warms ScreenCaptureKit and system privacy permissions in the background during app startup.
    func prewarm() {
        Task(priority: .background) {
            _ = try? await SCShareableContent.current
        }
    }

    // MARK: - UI Flow
    
    func startCapture() {
        isCaptureActive = true
        previousApp = NSWorkspace.shared.frontmostApplication
        Task { await showOverlay() }
    }
    
    private func showOverlay() async {
        guard overlayWindows.isEmpty else { return }
        do {
            streamContent = try await SCShareableContent.current
        } catch {
            log("Permission Error: \(error.localizedDescription)", type: .error)
            complete(with: nil)
            return
        }
        
        let onCaptureAction: (CGRect, NSScreen) -> Void = { [weak self] localRect, screen in
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordMouseRelease()
            #endif
            Task { @MainActor in
                guard let self = self else { return }
                // The first gesture to end wins.
                if !self.overlayWindows.isEmpty {
                    self.selectedRegion = CaptureSelection(rect: localRect, screen: screen)
                    self.closeOverlay()
                    if localRect != .zero {
                        await self.captureSelection()
                    } else {
                        self.complete(with: nil)
                    }
                }
            }
        }

        // Create one overlay window for each screen.
        for screen in NSScreen.screens {
            log("NSScreen Frame: \(screen.frame)")
            let captureView = CaptureView(onCapture: onCaptureAction, screen: screen)
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.sharingType = .none // Excludes overlay from ScreenCaptureKit recordings
            window.contentView = ActionHostingView(rootView: captureView)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.onEscape = { [weak self] in Task { @MainActor in self?.cancelCapture() } }
            overlayWindows.append(window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        overlayWindows.first?.makeKey()
        NSCursor.hide()
    }

    private func closeOverlay() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        NSCursor.unhide()
        
        // Restore the previously active application to prevent greyed-out windows
        if let app = previousApp {
            app.activate(options: [])
        }
        previousApp = nil
    }
    
    private func cancelCapture() {
        closeOverlay()
        complete(with: nil)
    }
    
    // MARK: - Capture Flow
    
    /// Captures the selected screen region instantly using macOS 14+ SCScreenshotManager.
    private func captureSelection() async {
        guard let content = streamContent, let selection = selectedRegion else {
            log("Error: Missing shareable content or selection data.", type: .error)
            complete(with: nil)
            return
        }
        
        guard let targetDisplay = findMatchingDisplay(for: selection.screen, in: content) else {
            log("Error: Could not find matching SCDisplay for screen.", type: .error)
            complete(with: nil)
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
            complete(with: cgImage)
        } catch {
            log("SCScreenshotManager capture failed: \(error.localizedDescription)", type: .error)
            complete(with: nil)
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
        let scaleFactor = selection.screen.backingScaleFactor
        
        config.sourceRect = selection.rect
        config.width = max(1, Int(selection.rect.width * scaleFactor))
        config.height = max(1, Int(selection.rect.height * scaleFactor))
        config.scalesToFit = true
        config.showsCursor = false
        
        return (filter, config)
    }
    
    private func complete(with image: CGImage?) {
        guard isCaptureActive else { return }
        isCaptureActive = false
        
        streamContent = nil
        let activeScreen = selectedRegion?.screen
        selectedRegion = nil
        
        log("Capture sequence completed. Success: \(image != nil)")
        onCaptureComplete?(image, activeScreen)
    }

    // MARK: - Logging helper
    
    private enum LogType { case info, error }
    
    private func log(_ message: String, type: LogType = .info) {
        let prefix = type == .error ? "[ScreenCaptureManager] ❌" : "[ScreenCaptureManager] ℹ️"
        debugPrint("\(prefix) \(message)")
    }
}
