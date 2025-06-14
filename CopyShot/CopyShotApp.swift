//
//  CopyShotApp.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // Add this line
    @MainActor
    private lazy var captureManager = ScreenCaptureManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.register()
        
        // Add these lines to listen for the hotkey notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidFire),
            name: .hotkeyWasPressed,
            object: nil
        )
    }
    
    // Add this new function
    @objc func hotkeyDidFire() {
        print("Hotkey fired! Starting capture...")
        Task { @MainActor in
                captureManager.onCaptureComplete = { image in
                    if let capturedImage = image {
                        print("Image captured successfully! Size: \(capturedImage.width)x\(capturedImage.height)")
                    } else {
                        print("Capture was cancelled or failed.")
                    }
                }
                
                captureManager.startCapture()
            }
    }
}

@main
struct CopyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // tells SwiftUI to create & manage an instance of AppD.
    var body: some Scene {
        Settings {
            // An empty settings view is fine for now.
        }
    }
}
