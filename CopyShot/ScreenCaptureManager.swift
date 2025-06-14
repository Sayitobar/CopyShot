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
    
    // MARK: - Properties
    
    private var overlayWindow: OverlayWindow
    private var hostingController: NSHostingController<CaptureView>?
    
    private var stream: SCStream?
    private var availableContent: SCShareableContent?
    private var selectedRegion: CGRect?
    
    var onCaptureComplete: ((CGImage?) -> Void)?
    
    // MARK: - Initializer
    
    override init() {
        overlayWindow = OverlayWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.level = .screenSaver
        
        super.init()
        
        // Set the escape key handler for our window
        overlayWindow.onEscape = { [weak self] in
            Task { @MainActor in
                self?.cancelCapture()
            }
        }
    }

    // MARK: - Public Capture Flow
    
    func startCapture() {
        Task {
            await self.getShareableContentAndShowOverlay()
        }
    }
    
    // MARK: - Private UI Flow

    private func getShareableContentAndShowOverlay() async {
        guard !overlayWindow.isVisible else { return }

        do {
            availableContent = try await SCShareableContent.current
        } catch {
            print("ScreenCaptureKit permission error: \(error.localizedDescription)")
            // TODO: In Phase 2, show a user-facing alert guiding them to Settings.
            return
        }
        
        showOverlay()
    }

    private func showOverlay() {
        let onCaptureAction: (CGRect) -> Void = { [weak self] rect in
            Task { @MainActor in
                guard let self = self else { return }
                
                if rect != .zero {
                    self.selectedRegion = rect
                    self.closeOverlay()
                    self.startScreenCaptureKitStream()
                } else {
                    self.cancelCapture()
                }
            }
        }

        let captureView = CaptureView(onCapture: onCaptureAction)
        hostingController = NSHostingController(rootView: captureView)
        overlayWindow.contentViewController = hostingController
        
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        guard let mainScreen = NSScreen.main else {
            print("Could not find main screen.")
            return
        }
        overlayWindow.setFrame(mainScreen.frame, display: true)
        
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow.makeKeyAndOrderFront(nil)
        
        // Set crosshair cursor and hide system one
        NSCursor.hide()
    }

    private func closeOverlay() {
        overlayWindow.orderOut(nil)
        hostingController = nil
        overlayWindow.contentViewController = nil
        
        // Restore default cursor
        NSCursor.unhide()
    }
    
    private func cancelCapture() {
        closeOverlay()
        onCaptureComplete?(nil)
    }
    
    // MARK: - Private ScreenCaptureKit Stream

    private func startScreenCaptureKitStream() {
        guard let display = availableContent?.displays.first, let region = selectedRegion else {
            complete(with: nil)
            return
        }
        
        let config = SCStreamConfiguration()
        let screenHeight = display.height
        let convertedRect = CGRect(x: region.origin.x, y: CGFloat(screenHeight) - region.origin.y - region.height, width: region.width, height: region.height)
        
        config.sourceRect = convertedRect
        config.width = Int(convertedRect.width)
        config.height = Int(convertedRect.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 1
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        do {
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            Task { try await stream?.startCapture() }
        } catch {
            print("Error starting ScreenCaptureKit stream: \(error.localizedDescription)")
            complete(with: nil)
        }
    }
    
    private func complete(with image: CGImage?) {
        DispatchQueue.main.async {
            self.onCaptureComplete?(image)
        }
    }

    // MARK: - SCStream Delegate Methods

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let firstAttachment = attachments.first,
              case .complete = firstAttachment[.status] as? SCFrameStatus else {
            return
        }
        
        Task {
            do { try await stream.stopCapture() }
            catch { print("Error stopping stream: \(error.localizedDescription)") }
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            Task { @MainActor in
                self.complete(with: nil)
            }
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            Task { @MainActor in
                self.complete(with: cgImage)
            }
        } else {
            Task { @MainActor in
                self.complete(with: nil)
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error.localizedDescription)")
        Task { @MainActor in
            self.complete(with: nil)
        }
    }
}
