//
//  CopyShotApp.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI
import UserNotifications

// By marking the AppDelegate with @MainActor, we ensure all its methods
// and properties are on the main thread, resolving the core conflict.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // The manager is now created on the main actor, which is safe.
    private let captureManager = ScreenCaptureManager()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("--- App is ready. Setting up services. ---")
        
        requestNotificationPermission()
        UNUserNotificationCenter.current().delegate = self
        
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
                        FeedbackManager.showNotification(
                            title: "No Text Found",
                            body: "The selected area did not contain any recognizable text."
                        )
                    } else {
                        print("Successfully recognized text. Copying to clipboard.")
                        ClipboardManager.copyToClipboard(text: recognizedText)
                        
                        FeedbackManager.showNotification(
                            title: "Text Copied",
                            body: "The recognized text has been copied to your clipboard."
                        )
                        // Also play the sound on success.
                        FeedbackManager.playSuccessSound()
                    }
                case .failure(let error):
                    print("OCR failed with error: \(error.localizedDescription)")
                    FeedbackManager.showNotification(
                        title: "OCR Failed",
                        body: "Could not recognize text. Please try again."
                    )
                }
            }
        }
        
        // 2. Register and listen for hotkeys.
        HotkeyManager.shared.registerHotkeys()
        
        // Listen for capture hotkey
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureHotkeyDidFire),
            name: .captureHotkeyPressed,
            object: nil
        )
        
        // Listen for settings hotkey
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsHotkeyDidFire),
            name: .settingsHotkeyPressed,
            object: nil
        )
        
        print("--- Setup complete. Waiting for hotkeys. ---")
    }
    
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied.")
            }
        }
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // By returning .banner, we tell the system to show the notification
        // as a banner even if our app is in the foreground.
        completionHandler([.banner, .sound, .list])
    }
    
    // This function handles the capture hotkey.
    @objc func captureHotkeyDidFire() {
        print("--- Capture hotkey fired! Starting capture... ---")
        captureManager.startCapture()
    }
    
    // This function handles the settings hotkey.
    @objc func settingsHotkeyDidFire() {
        print("--- Settings hotkey fired! Opening settings... ---")
        openSettings()
    }
    
    private func openSettings() {
        // Open the settings window
        if let settingsWindow = settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create settings window if it doesn't exist
            let settingsView = SettingsView()
                .environmentObject(SettingsManager.shared)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "CopyShot Settings"
            window.contentView = NSHostingView(rootView: settingsView)
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            self.settingsWindow = window
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@main
struct CopyShotApp: App {
    // Keep the AppDelegate to manage the hotkey and background tasks.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // We need to access our settings to pass them to the SettingsView.
    @StateObject private var settings = SettingsManager.shared

    var body: some Scene {
        // This is the primary scene for a Menu Bar app.
        MenuBarExtra("CopyShot", systemImage: "text.viewfinder") {
            
            // This is the content of the menu that appears when you click the icon.
            
            Button("Capture Text") {
                // Manually trigger the capture flow.
                appDelegate.captureHotkeyDidFire()
            }
            
            Divider()
            
            // This special button automatically opens our Settings scene.
            SettingsLink()
            
            Divider()
            
            Button("Quit CopyShot") {
                NSApplication.shared.terminate(nil)
            }
            
        }
        
        // This defines the window that opens when the user clicks the SettingsLink.
        // It's a separate, secondary scene.
        Settings {
            SettingsView()
                .environmentObject(settings) // Pass the settings manager to the view
        }
    }
}
