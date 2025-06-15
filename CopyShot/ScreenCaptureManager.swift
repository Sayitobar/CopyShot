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
    private var selectedRegion: CGRect?
    private var streamContent: SCShareableContent?
    var onCaptureComplete: ((CGImage?) -> Void)?

    // MARK: - UI Flow
    func startCapture() {
        Task { await showOverlay() }
    }
    
    private func showOverlay() async {
        guard overlayWindows.isEmpty else { return }
        do {
            streamContent = try await SCShareableContent.current
        } catch {
            print("Permission Error: \(error.localizedDescription)")
            onCaptureComplete?(nil)
            return
        }
        
        let onCaptureAction: (CGRect) -> Void = { [weak self] rect in
            Task { @MainActor in
                guard let self = self else { return }
                // The first gesture to end wins.
                if !self.overlayWindows.isEmpty {
                    self.selectedRegion = rect
                    self.closeOverlay()
                    if rect != .zero { self.startStream() }
                    else { self.onCaptureComplete?(nil) }
                }
            }
        }

        // Create one overlay window for each screen.
        for screen in NSScreen.screens {
            let captureView = CaptureView(onCapture: onCaptureAction)
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.contentView = NSHostingView(rootView: captureView)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.onEscape = { [weak self] in Task { @MainActor in self?.cancelCapture() } }
            overlayWindows.append(window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        NSCursor.hide()
    }

    private func closeOverlay() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        NSCursor.unhide()
    }
    
    private func cancelCapture() {
        closeOverlay()
        onCaptureComplete?(nil)
    }
    
    // MARK: - Capture Flow
    private func startStream() {
        guard let content = streamContent, let selection = selectedRegion else {
            complete(with: nil)
            return
        }
        
        let selectionCenter = CGPoint(x: selection.midX, y: selection.midY)
        guard let targetDisplay = content.displays.first(where: { $0.frame.contains(selectionCenter) }) else {
            print("Error: Could not find a display for the selected region.")
            complete(with: nil)
            return
        }
        
        let filter = SCContentFilter(display: targetDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = targetDisplay.width
        config.height = targetDisplay.height
        config.scalesToFit = true
        config.queueDepth = 5
        
        do {
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            Task { try await stream?.startCapture() }
        } catch {
            print("Error starting stream: \(error.localizedDescription)")
            complete(with: nil)
        }
    }
    
    nonisolated private func complete(with image: CGImage?) {
        DispatchQueue.main.async { self.onCaptureComplete?(image) }
    }

    // MARK: - SCStream Delegate
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        Task { do { try await stream.stopCapture() } catch {} }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { complete(with: nil); return }
        let fullDisplayImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let fullDisplayCGImage = context.createCGImage(fullDisplayImage, from: fullDisplayImage.extent) else { complete(with: nil); return }
        
        Task { @MainActor in
            guard let selection = self.selectedRegion, let content = self.streamContent else { complete(with: nil); return }
            let selectionCenter = CGPoint(x: selection.midX, y: selection.midY)
            guard let targetDisplay = content.displays.first(where: { $0.frame.contains(selectionCenter) }) else { complete(with: nil); return }
            
            let cropRect = CGRect(
                x: selection.origin.x - targetDisplay.frame.origin.x,
                y: selection.origin.y - targetDisplay.frame.origin.y,
                width: selection.width,
                height: selection.height
            )

            if let croppedCGImage = fullDisplayCGImage.cropping(to: cropRect) {
                complete(with: croppedCGImage)
            } else {
                complete(with: nil)
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        complete(with: nil)
    }
}
