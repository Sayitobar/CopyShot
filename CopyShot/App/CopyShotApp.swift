//
//  CopyShotApp.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import SwiftUI
import UserNotifications
import Sparkle

// By marking the AppDelegate with @MainActor, we ensure all its methods
// and properties are on the main thread, resolving the core conflict.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // The manager is now created on the main actor, which is safe.
    private let captureManager = ScreenCaptureManager()

    private lazy var capturePipeline = CapturePipeline(
        isLatest: { [weak self] requestID in
            self?.captureManager.isLatestCapture(requestID) ?? false
        },
        recognize: { image, completion in
            OCRService.performOCR(on: image) { result in
                Task { @MainActor in completion(result) }
            }
        },
        deliver: { [weak self] outcome, screen in
            self?.presentCaptureOutcome(outcome, screen: screen)
        }
    )
    
    @Published var menuBarIconState: MenuBarIconState = .idle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugPrint("--- App is ready. Setting up services. ---")
        
        // 1. Set up the completion handler ONCE.
        // This is now safe because both the AppDelegate and the captureManager
        // are on the Main Actor.
        captureManager.onCaptureComplete = { [weak self] image, screen, requestID in
            self?.capturePipeline.completeCapture(image: image, screen: screen, requestID: requestID)
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
        
        // 3. Pre-warm ScreenCaptureKit in background to eliminate cold-start daemon delay
        captureManager.prewarm()

        if ProcessInfo.processInfo.arguments.contains("--ui-testing-show-settings") {
            DispatchQueue.main.async {
                SettingsWindowManager.shared.showSettings()
            }
        }
        
        debugPrint("--- Setup complete. Waiting for hotkeys. ---")
    }
    
    
    // This function handles the capture hotkey.
    @objc func captureHotkeyDidFire() {
        debugPrint("--- Capture hotkey fired! Starting capture... ---")
        menuBarIconState = .capturing
        captureManager.startCapture()
    }

    private func presentCaptureOutcome(_ outcome: CapturePipeline.Outcome, screen: NSScreen?) {
        switch outcome {
        case .cancelled:
            FeedbackManager.showNotification(
                title: "Capture Cancelled",
                body: "The screen capture was cancelled or failed.",
                iconName: "xmark.circle.fill",
                accentColor: .adaptiveRed,
                soundName: "Frog",
                targetScreen: screen
            )
            resetIcon()
        case .noText:
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordOCRCompleted()
            #endif
            FeedbackManager.showNotification(
                title: "No Text Found",
                body: "The selected area did not contain any recognizable text.",
                iconName: "questionmark.circle.fill",
                accentColor: .adaptiveBlue,
                soundName: "Bottle",
                targetScreen: screen
            )
            resetIcon()
        case .text(let recognizedText):
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordOCRCompleted()
            #endif
            ClipboardManager.copyToClipboard(text: recognizedText)
            FeedbackManager.showNotification(
                title: "Text Copied",
                subtitle: "Recognized text:",
                body: TextPreview.format(recognizedText, limit: SettingsManager.shared.textPreviewLimit),
                fullBody: recognizedText,
                iconName: "checkmark.circle.fill",
                accentColor: .adaptiveGreen,
                soundName: "Funk",
                targetScreen: screen,
                supportsQuickActions: SettingsManager.shared.quickActionsConfig.isEnabled
            )
            setSuccessIcon()
        case .failed(let error):
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordOCRCompleted()
            #endif
            FeedbackManager.showNotification(
                title: "OCR Failed",
                body: error.localizedDescription,
                iconName: "exclamationmark.triangle.fill",
                accentColor: .adaptiveOrange,
                soundName: "Sosumi",
                targetScreen: screen
            )
            resetIcon()
        }
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

import Combine

// Wrapper class to make the Updater conform to ObservableObject for SwiftUI
final class UpdaterViewModel: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.automaticallyChecksForUpdates = self.controller.updater.automaticallyChecksForUpdates
        
        self.controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }
    
    func checkForUpdates() {
        self.controller.checkForUpdates(nil)
    }
}

@main
struct CopyShotApp: App {
    // Keep the AppDelegate to manage the hotkey and background tasks.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // We need to access our settings to pass them to the SettingsView.
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var notificationPresenter = FeedbackManager.shared.presenter
    
    // Sparkle auto-updater controller wrapper
    @StateObject private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        // This is the primary scene for a Menu Bar app.
        MenuBarExtra(content: {
            CopyShotMenu(appDelegate: appDelegate, updaterViewModel: updaterViewModel)
        }, label: {
            let state = appDelegate.menuBarIconState
            if state == .idle {
                // Resize the custom asset to be menu-bar friendly (e.g. 18x18 pts)
                // This prevents large images from blowing up the menu bar size.
                if let nsImage = NSImage(named: state.rawValue) {
                    Image(nsImage: {
                        nsImage.size = NSSize(width: 22, height: 22)
                        return nsImage
                    }())
                } else {
                    Image(systemName: "camera.viewfinder") // Fallback
                }
            } else {
                 Image(systemName: state.rawValue) // SF Symbol
            }
        })
    }
}

struct CopyShotMenu: View {
    var appDelegate: AppDelegate
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        Button("Capture Text") {
            // Manually trigger the capture flow.
            appDelegate.captureHotkeyDidFire()
        }
        
        Divider()
        
        Button("Settings...") {
            SettingsWindowManager.shared.showSettings(updaterViewModel: updaterViewModel)
        }
        .keyboardShortcut(",", modifiers: .command)
        
        Button("Check for Updates...") {
            updaterViewModel.checkForUpdates()
        }
        .disabled(!updaterViewModel.canCheckForUpdates)
        
        Divider()
        
        Button("Quit CopyShot") {
            NSApplication.shared.terminate(nil)
        }
        .preferredColorScheme(SettingsManager.shared.appearance.colorScheme)
    }
}
