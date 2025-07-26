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
    struct CaptureSelection {
    let rect: CGRect
    let screen: NSScreen
}

    private var selectedRegion: CaptureSelection?
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
        
        let onCaptureAction: (CGRect, NSScreen) -> Void = { [weak self] localRect, screen in
            Task { @MainActor in
                guard let self = self else { return }
                // The first gesture to end wins.
                if !self.overlayWindows.isEmpty {
                    self.selectedRegion = CaptureSelection(rect: localRect, screen: screen)
                    self.closeOverlay()
                    if localRect != .zero { self.startStream() }
                    else { self.onCaptureComplete?(nil) }
                }
            }
        }

        // Create one overlay window for each screen.
        for screen in NSScreen.screens {
            print("NSScreen Frame: \(screen.frame)")
            let captureView = CaptureView(onCapture: onCaptureAction, screen: screen)
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
        onCaptureComplete?(nil)
    }
    
    // MARK: - Capture Flow
    private func startStream() {
        guard let content = streamContent, let selectionData = selectedRegion else {
            complete(with: nil)
            return
        }
        
        print("--- NSScreen frames ---")
        for screen in NSScreen.screens {
            print("NSScreen Frame: \(screen.frame)")
        }
        print("-----------------------")
        
        print("--- SCShareableContent.current.displays frames ---")
        for display in content.displays {
            print("SCDisplay Frame: \(display.frame)")
        }
        print("--------------------------------------------------")
        
        // Find the SCDisplay matching the NSScreen where the selection was made by matching x, width, and height
        guard let targetDisplay = content.displays.first(where: {
            $0.frame.origin.x == selectionData.screen.frame.origin.x &&
            $0.frame.width == selectionData.screen.frame.width &&
            $0.frame.height == selectionData.screen.frame.height
        }) else {
            print("Error: Could not find a capturable display for the selected screen.")
            complete(with: nil)
            return
        }
        
        let filter = SCContentFilter(display: targetDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        
        // Calculate the sourceRect relative to the targetDisplay's origin
        // The localRect from CaptureView is relative to the NSScreen's frame (top-left origin)
        // SCDisplay frame has a bottom-left origin.
        
        print("\n--- Source Rect Calculation Inputs ---")
        print("selectionData.rect (localRect): \(selectionData.rect)")
        print("selectionData.screen.frame: \(selectionData.screen.frame)")
        print("targetDisplay.frame: \(targetDisplay.frame)")
        print("--------------------------------------")
        
        let sourceRect = CGRect(
            x: selectionData.rect.origin.x,
            y: selectionData.rect.origin.y, // Assuming top-left origin for sourceRect
            width: selectionData.rect.width,
            height: selectionData.rect.height
        )
        config.sourceRect = sourceRect // Set the sourceRect
        
        config.width = Int(selectionData.rect.width) // Set width to selection width
        config.height = Int(selectionData.rect.height) // Set height to selection height
        config.scalesToFit = true
        config.queueDepth = 5
        
        print("Calculated sourceRect: \(sourceRect)")
        print("Target Display Frame for SCStream: \(targetDisplay.frame)")
        
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
            let selectionCenter = CGPoint(x: selection.rect.midX, y: selection.rect.midY)
            guard let targetDisplay = content.displays.first(where: { $0.frame.contains(selectionCenter) }) else { complete(with: nil); return }
            
            complete(with: fullDisplayCGImage)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        complete(with: nil)
    }
}
