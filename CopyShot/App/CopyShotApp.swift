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
    private lazy var formulaService: FormulaRecognizing = FormulaRecognitionService()

    private lazy var capturePipeline = CapturePipeline(
        isLatest: { [weak self] requestID in
            self?.captureManager.isLatestCapture(requestID) ?? false
        },
        recognizers: [
            .standardOCR: { image, completion in
                OCRService.performOCR(on: image) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let text): completion(.success(.standardText(text)))
                        case .failure(let error): completion(.failure(error))
                        }
                    }
                }
            },
            .qrBarcode: { image, completion in
                BarcodeRecognitionService.recognize(image) { result in
                    Task { @MainActor in completion(result.map(CaptureResult.barcodes)) }
                }
            },
            .latex: { [weak self] image, completion in
                self?.formulaService.recognize(image) { result in
                    Task { @MainActor in
                        completion(result.map {
                            CaptureResult.latex(
                                formula: $0.formula,
                                statusNote: $0.wasSyntaxFixed ? "Fixed broken syntax" : nil
                            )
                        })
                    }
                }
            },
            .table: { image, completion in
                TableRecognitionService.recognize(image) { result in
                    Task { @MainActor in completion(result.map(CaptureResult.table)) }
                }
            }
        ],
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
        captureManager.onCaptureComplete = { [weak self] image, screen, mode, requestID in
            self?.capturePipeline.completeCapture(image: image, screen: screen, mode: mode, requestID: requestID)
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
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-qa-fixture") {
                    let context = ActionContext(payload: .barcodes((0..<36).map {
                        DetectedBarcode(payload: "Sample barcode \($0 + 1)", symbology: "QR")
                    }))
                    FeedbackManager.shared.presenter.showNotification(
                        title: "Barcode Fixture", body: "36 synthetic barcode payloads", fullBody: context.text,
                        accentColor: .adaptiveGreen, duration: 120, supportsQuickActions: true, actionContext: context
                    )
                }
                #endif
            }
        }
        
        debugPrint("--- Setup complete. Waiting for hotkeys. ---")
    }
    
    
    // This function handles the capture hotkey.
    @objc func captureHotkeyDidFire() {
        debugPrint("--- Capture hotkey fired! Starting capture... ---")
        menuBarIconState = .capturing
        FeedbackManager.shared.presenter.dismissNotification()
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
        case .noContent(let mode):
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordOCRCompleted()
            #endif
            FeedbackManager.showNotification(
                title: mode == .standardOCR ? "No Text Found" : mode == .qrBarcode ? "No Barcode Found" : "No Content Found",
                body: mode == .standardOCR
                    ? "The selected area did not contain any recognizable text."
                    : "The selected area did not contain recognizable \(CaptureModeDescriptor.descriptor(for: mode)?.title ?? "content").",
                iconName: "questionmark.circle.fill",
                accentColor: .adaptiveBlue,
                soundName: "Bottle",
                targetScreen: screen
            )
            resetIcon()
        case .result(let result):
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordOCRCompleted()
            #endif
            let presentation: (title: String, subtitle: String, text: String, quickActions: Bool, mode: CaptureMode)
            switch result {
            case .standardText(let text):
                presentation = ("Text Copied", "Recognized text:", text, true, .standardOCR)
            case .barcodes(let codes):
                presentation = ("Barcode Copied", "Detected code:", codes.map(\.payload).joined(separator: "\n"), true, .qrBarcode)
            case .latex(let formula, let statusNote):
                let subtitle = statusNote ?? "Recognized formula:"
                presentation = ("LaTeX Copied", subtitle, formula, true, .latex)
            case .table(let table):
                presentation = ("Table Copied", "Recognized cells:", table.tabSeparatedText, true, .table)
            }
            ClipboardManager.copyToClipboard(text: presentation.text)
            FeedbackManager.showNotification(
                title: presentation.title,
                subtitle: presentation.subtitle,
                body: TextPreview.format(presentation.text, limit: SettingsManager.shared.textPreviewLimit),
                fullBody: presentation.text,
                iconName: "checkmark.circle.fill",
                accentColor: .adaptiveGreen,
                soundName: "Funk",
                targetScreen: screen,
                supportsQuickActions: presentation.quickActions && SettingsManager.shared.quickActionsConfig.isEnabled,
                captureMode: presentation.mode,
                actionContext: ActionContext(payload: result)
            )
            setSuccessIcon()
        case .failed(let mode, let error):
            #if DEBUG
            CaptureBenchmarkTracker.shared.recordOCRCompleted()
            #endif
            FeedbackManager.showNotification(
                title: "\(CaptureModeDescriptor.descriptor(for: mode)?.title ?? "Capture") Failed",
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
