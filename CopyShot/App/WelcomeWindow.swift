import AppKit
import Combine
import SwiftUI

private struct WelcomeSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct WelcomeContent: View {
    @ObservedObject var settings: SettingsManager
    let contentWidth: CGFloat
    let capture: () -> Void
    let openSettings: () -> Void
    let resize: (CGSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName)!)
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to CopyShot").font(.title2.weight(.semibold))
                    Text("Capture, copy, and understand the result.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                step("Capture and paste", icon: "viewfinder", text: "Press \(settings.captureHotkey.displayString), then drag over text.\n\nThe result is copied automatically. Paste with ⌘V. Escape cancels a selection.")
                step("Choose a capture mode", icon: "circle.grid.2x2", text: "During capture, right-click and drag to choose OCR, QR/barcodes, LaTeX, or tables.\n\nLaTeX needs a one-time 120 MB model download.")
                step("Quick Actions", icon: "bolt", text: "Hover the result notification to transform text, search, open links, or export a table.\n\nConfigure actions in Settings. Translation needs macOS 15+ and Apple language packs.")
                step("Inspect the result", icon: "magnifyingglass", text: "Enable Inspect Capture in Settings → Quick Actions → OCR.\n\nCompare processing stages and detected text regions. Inspection is optional and off by default.")
            }
            Divider()
            Text("First capture: Allow CopyShot in System Settings → Privacy & Security → Screen & System Audio Recording. Quit and reopen if required.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("Recognition stays on your Mac. Web and URL actions send text to your chosen destination. Custom scripts run outside CopyShot's sandbox with your user permissions; only install scripts you trust. Captured text is placed on the macOS clipboard. CopyShot keeps no capture history.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welcome-data-boundaries")
            HStack {
                Link("Read the guide", destination: URL(string: "https://github.com/Sayitobar/CopyShot/blob/main/docs/USAGE.md")!)
                    .font(.caption)
                Spacer()
                Button("Settings…", action: openSettings)
                    .accessibilityIdentifier("welcome-settings")
                Button("Start Capture", action: capture)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("welcome-start-capture")
            }
        }
        .padding(24)
        .frame(width: contentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in Color.clear.preference(key: WelcomeSizeKey.self, value: proxy.size) })
        .onPreferenceChange(WelcomeSizeKey.self, perform: resize)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    private func step(_ title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(Color.accentColor)
                .frame(height: 28).accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// A first-launch introduction, measured from its content; Debug Zones exposes reopening.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()
    private var window: NSWindow?
    private var appearanceObserver: AnyCancellable?

    func showIfNeeded(settings: SettingsManager = .shared, capture: @escaping () -> Void) {
        guard !settings.hasSeenWelcome else { return }
        show(settings: settings, capture: capture)
    }

    func show(settings: SettingsManager = .shared, capture: @escaping () -> Void) {
        settings.hasSeenWelcome = true
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome to CopyShot"
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            let content = WelcomeContent(settings: settings,
                contentWidth: min(960, NSScreen.main?.visibleFrame.width ?? 960),
                capture: { [weak self] in self?.close(); capture() },
                openSettings: { [weak self] in self?.close(); SettingsWindowManager.shared.showSettings() },
                resize: { [weak self] in self?.resize($0) })
            let host = NSHostingView(rootView: content)
            window.contentView = host
            window.setContentSize(host.fittingSize)
            appearanceObserver = settings.$appearance.sink { [weak window] appearance in
                switch appearance {
                case .system: window?.appearance = nil
                case .light: window?.appearance = NSAppearance(named: .aqua)
                case .dark: window?.appearance = NSAppearance(named: .darkAqua)
                }
            }
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func resize(_ size: CGSize) {
        guard let window, window.contentView?.frame.size != size else { return }
        let top = window.frame.maxY
        window.setContentSize(size)
        if window.isVisible { window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height)) }
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        appearanceObserver = nil
        window?.contentView = nil
        window = nil
    }
}
