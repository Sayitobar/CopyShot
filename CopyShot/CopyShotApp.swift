//
//  CopyShotApp.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI

// By marking the AppDelegate with @MainActor, we ensure all its methods
// and properties are on the main thread, resolving the core conflict.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // The manager is now created on the main actor, which is safe.
    private let captureManager = ScreenCaptureManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("--- App is ready. Setting up services. ---")
        
        // 1. Set up the completion handler ONCE.
        // This is now safe because both the AppDelegate and the captureManager
        // are on the Main Actor.
        captureManager.onCaptureComplete = { image in
            print("--- AppDelegate: onCaptureComplete closure EXECUTED. ---")
            
            guard let capturedImage = image else {
                print("Capture was cancelled or failed.")
                return
            }
            
            print("Image captured successfully. Performing OCR...")
            
            // The OCR service runs on a background thread internally,
            // so this call does not block the main thread.
            OCRService.performOCR(on: capturedImage) { result in
                switch result {
                case .success(let recognizedText):
                    if recognizedText.isEmpty {
                        print("OCR completed, but no text was found.")
                    } else {
                        print("Successfully recognized text. Copying to clipboard.")
                        ClipboardManager.copyToClipboard(text: recognizedText)
                    }
                case .failure(let error):
                    print("OCR failed with error: \(error.localizedDescription)")
                }
            }
        }
        
        // 2. Register and listen for the hotkey.
        HotkeyManager.shared.register()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidFire),
            name: .hotkeyWasPressed,
            object: nil
        )
        
        print("--- Setup complete. Waiting for hotkey. ---")
    }
    
    // This function is now also on the Main Actor.
    @objc func hotkeyDidFire() {
        print("--- Hotkey fired! Starting capture... ---")
        // Since this function and startCapture() are both on the Main Actor,
        // we no longer need to wrap the call in a Task. We can call it directly.
        captureManager.startCapture()
    }
}

// The rest of the file remains the same
@main
struct CopyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { }
    }
}
