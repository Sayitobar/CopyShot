//
//  ScreenCaptureManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI
import ScreenCaptureKit

@MainActor
class ScreenCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    
    private var overlayWindows: [OverlayWindow] = []
    private var stream: SCStream?
    private var isCaptureActive = false
    struct CaptureSelection {
    let rect: CGRect
    let screen: NSScreen
}

    private var selectedRegion: CaptureSelection?
    private var streamContent: SCShareableContent?
    var onCaptureComplete: ((CGImage?) -> Void)?

    // MARK: - UI Flow
    func startCapture() {
        isCaptureActive = true
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
            Task { @MainActor in
                guard let self = self else { return }
                // The first gesture to end wins.
                if !self.overlayWindows.isEmpty {
                    self.selectedRegion = CaptureSelection(rect: localRect, screen: screen)
                    self.closeOverlay()
                    if localRect != .zero { self.startStream() }
                    else { self.complete(with: nil) }
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
    }
    
    private func cancelCapture() {
        closeOverlay()
        complete(with: nil)
    }
    
    // MARK: - Capture Flow
    
    /// Starts the ScreenCaptureKit stream for the selected region.
    private func startStream() {
        guard let content = streamContent, let selection = selectedRegion else {
            log("Error: Missing stream content or selection data.", type: .error)
            complete(with: nil)
            return
        }
        
        log("Identifying target display for capture...")
        
        guard let screenNumber = selection.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            log("Error: Could not get screen number from NSScreen.", type: .error)
            complete(with: nil)
            return
        }
        
        // Match the selection screen to a SCDisplay based on the hardware display ID.
        guard let targetDisplay = content.displays.first(where: { $0.displayID == screenNumber }) else {
            log("Error: Could not find a matching SCDisplay for the selected screen.", type: .error)
            complete(with: nil)
            return
        }
        
        // Configure the stream
        let filter = SCContentFilter(display: targetDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        
        let scaleFactor = selection.screen.backingScaleFactor
        
        // Map the point-based selection rect to the display's coordinate space.
        let sourceRect = CGRect(
            x: selection.rect.origin.x,
            y: selection.rect.origin.y,
            width: selection.rect.width,
            height: selection.rect.height
        )
        
        config.sourceRect = sourceRect
        
        // Set the output alignment to pixel dimensions for Retina quality.
        config.width = Int(selection.rect.width * scaleFactor)
        config.height = Int(selection.rect.height * scaleFactor)
        config.scalesToFit = true
        config.queueDepth = 1
        
        log("Stream Configuration: SourceRect=\(sourceRect) OutputSize=\(config.width)x\(config.height) Scale=\(scaleFactor)")
        
        do {
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            
            Task {
                log("Starting SCStream...")
                try await stream?.startCapture()
            }
        } catch {
            log("Failed to start stream: \(error.localizedDescription)", type: .error)
            complete(with: nil)
        }
    }
    
    nonisolated private func complete(with image: CGImage?) {
        Task { @MainActor in
            guard self.isCaptureActive else { return }
            self.isCaptureActive = false
            self.log("Capture sequence completed. Success: \(image != nil)")
            self.onCaptureComplete?(image)
        }
    }

    // MARK: - SCStream Delegate
    
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Immediately stop the stream as we only need one frame.
        Task {
            do { try await stream.stopCapture() } catch {
                // Ignore stop errors, as we are done anyway.
            }
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            log("Stream output failed: Could not get image buffer.", type: .error)
            complete(with: nil)
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        // Convert to CGImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            log("Stream output failed: Could not create CGImage.", type: .error)
            complete(with: nil)
            return
        }
        
        Task { @MainActor in
            // Guard against edge cases where selection was cleared
            guard self.selectedRegion != nil else {
                complete(with: nil)
                return
            }
            log("Frame captured successfully.")
            complete(with: cgImage)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("Stream stopped with error: \(error.localizedDescription)", type: .error)
        complete(with: nil)
    }
    // MARK: - Logging helper
    private enum LogType { case info, error }
    
    nonisolated private func log(_ message: String, type: LogType = .info) {
        let prefix = type == .error ? "[ScreenCaptureManager] ❌" : "[ScreenCaptureManager] ℹ️"
        debugPrint("\(prefix) \(message)")
    }
}
