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
    
    @Published var menuBarIconState: MenuBarIconState = .idle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugPrint("--- App is ready. Setting up services. ---")
        
        // No longer requesting UNNotification permission as we are using custom notifications.
        // UNUserNotificationCenter.current().delegate = self
        
        // 1. Set up the completion handler ONCE.
        // This is now safe because both the AppDelegate and the captureManager
        // are on the Main Actor.
        captureManager.onCaptureComplete = { image in
            debugPrint("--- AppDelegate: onCaptureComplete closure EXECUTED. ---")
            
            guard let capturedImage = image else {
                debugPrint("Capture was cancelled or failed.")
                FeedbackManager.showNotification(
                    title: "Capture Cancelled",
                    body: "The screen capture was cancelled or failed.",
                    iconName: "xmark.circle.fill",
                    accentColor: .gray,
                    soundName: "Frog" // Custom sound for cancellation
                )
                self.resetIcon()
                return
            }
            
            debugPrint("Image captured successfully. Performing OCR...")
            
            // The OCR service runs on a background thread internally,
            // so this call does not block the main thread.
            OCRService.performOCR(on: capturedImage) { result in
                switch result {
                case .success(let recognizedText):
                    if recognizedText.isEmpty {
                        debugPrint("OCR completed, but no text was found.")
                        FeedbackManager.showNotification(
                            title: "No Text Found",
                            body: "The selected area did not contain any recognizable text.",
                            iconName: "xmark.circle.fill",
                            accentColor: .red,
                            soundName: "Bottle" // Custom sound for no text found
                        )
                        self.resetIcon()
                    } else {
                        debugPrint("Successfully recognized text. Copying to clipboard.")
                        ClipboardManager.copyToClipboard(text: recognizedText)
                        
                        let previewText: String
                        if SettingsManager.shared.textPreviewLimit > 0 && recognizedText.count > SettingsManager.shared.textPreviewLimit {
                            previewText = String(recognizedText.prefix(SettingsManager.shared.textPreviewLimit)) + "..."
                        } else {
                            previewText = recognizedText
                        }
                        
                        FeedbackManager.showNotification(
                            title: "Text Copied",
                            subtitle: "The recognized text has been copied to your clipboard.",
                            body: previewText,
                            iconName: "checkmark.circle.fill",
                            accentColor: .green,
                            soundName: "Funk"
                        )
                        self.setSuccessIcon()
                    }
                case .failure(let error):
                    debugPrint("OCR failed with error: \(error.localizedDescription)")
                    FeedbackManager.showNotification(
                        title: "OCR Failed",
                        body: error.localizedDescription,
                        iconName: "exclamationmark.triangle.fill",
                        accentColor: .orange,
                        soundName: "Sosumi" // Custom sound for OCR failure
                    )
                    self.resetIcon()
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
        
        debugPrint("--- Setup complete. Waiting for hotkeys. ---")
    }
    
    private func requestNotificationPermission() {
        // No longer needed for custom notifications
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // No longer needed for custom notifications
    }
    
    // This function handles the capture hotkey.
    @objc func captureHotkeyDidFire() {
        debugPrint("--- Capture hotkey fired! Starting capture... ---")
        menuBarIconState = .capturing
        captureManager.startCapture()
    }
    
    private func setSuccessIcon() {
        menuBarIconState = .success
        // After a delay, revert to the idle icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.menuBarIconState = .idle
        }
    }
    
    private func resetIcon() {
        menuBarIconState = .idle
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
    @StateObject private var notificationPresenter = FeedbackManager.shared.presenter

    var body: some Scene {
        // This is the primary scene for a Menu Bar app.
        MenuBarExtra("CopyShot", systemImage: appDelegate.menuBarIconState.rawValue) {
            CopyShotMenu(appDelegate: appDelegate)
        }
        
        // This defines the window that opens when the user clicks the SettingsLink.
        // It's a separate, secondary scene.
        Settings {
            SettingsView()
                .environmentObject(settings) // Pass the settings manager to the view
        }
    }
}

struct CopyShotMenu: View {
    var appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Button("Capture Text") {
            // Manually trigger the capture flow.
            appDelegate.captureHotkeyDidFire()
        }
        
        Divider()
        
        if #available(macOS 14.0, *) {
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        } else {
            SettingsLink {
                Text("Settings...")
            }
        }
        
        Divider()
        
        Button("Quit CopyShot") {
            NSApplication.shared.terminate(nil)
        }
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
    }
    
    // Fallback for openSettings on older OS versions where the environment key might not be available or strictly typed?
    // Actually @Environment(\.openSettings) is non-optional in signature but only available on 14.0+.
    // The #available check guards the usage.
}
