import AppKit
import SwiftUI
import Combine

@MainActor
final class OCRInspectionWindow: NSObject, NSWindowDelegate {
    static let shared = OCRInspectionWindow()
    private var window: NSWindow?
    private var appearanceObserver: AnyCancellable?

    func show(record: OCRInspection, currentText: String, settings: SettingsManager = .shared) {
        if window == nil {
            let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: min(1180, screen.width * 0.9),
                                                     height: min(760, screen.height * 0.85)),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Capture Inspection"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.level = .normal
            window.delegate = self
            window.center()
            self.window = window
        }
        guard let window else { return }
        window.contentView = NSHostingView(rootView: OCRInspectionView(
            record: record, currentText: currentText,
            close: { [weak self] in self?.window?.close() },
            measureChrome: { [weak window] height in
                // Minimum viewport plus measured header and flow. No titlebar compensation offsets.
                window?.contentMinSize = CGSize(width: 820, height: height + 280)
            }, settings: settings)
            .id(record.id).ignoresSafeArea(.container, edges: .top))
        appearanceObserver = settings.$appearance.sink { [weak window] appearance in
            switch appearance {
            case .system: window?.appearance = nil
            case .light: window?.appearance = NSAppearance(named: .aqua)
            case .dark: window?.appearance = NSAppearance(named: .darkAqua)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        appearanceObserver = nil
        window = nil
    }
}
