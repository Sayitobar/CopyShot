import AppKit
import Combine
import SwiftUI

/// Native auxiliary window content, independent of Settings' tab sizing probes.
private struct SettingsResetContent: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var updater: UpdaterViewModel
    @State private var selected: Set<SettingsResetPage> = []
    let close: () -> Void
    let resize: (CGSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Reset Settings", systemImage: "arrow.counterclockwise")
                .font(.headline)
            Text("Choose the pages to restore to their defaults. Other pages keep their settings.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(SettingsResetPage.allCases) { page in
                    Toggle(page.title, isOn: Binding(
                        get: { selected.contains(page) },
                        set: { if $0 { selected.insert(page) } else { selected.remove(page) } }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("settings-reset-page-\(page.rawValue)")
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            Text("Custom scripts and URL actions are kept. Resetting Quick Actions restores ordering and options, and disables custom actions.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings-reset-cancel")
                Button("Reset Selected", role: .destructive) {
                    settings.reset(pages: selected)
                    if selected.contains(.general) {
                        updater.automaticallyChecksForUpdates = Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false
                    }
                    close()
                }
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("settings-reset-confirm")
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(settings.appearance.colorScheme)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: SettingsResetSizeKey.self, value: geometry.size)
        })
        .onPreferenceChange(SettingsResetSizeKey.self, perform: resize)
    }
}

private struct SettingsResetSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

@MainActor
final class SettingsResetWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsResetWindow()
    private var window: NSWindow?
    private var appearanceObserver: AnyCancellable?

    func show(settings: SettingsManager, updater: UpdaterViewModel) {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Reset Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            let content = SettingsResetContent(
                close: { [weak self] in self?.window?.close() },
                resize: { [weak self] size in self?.resize(size) })
                .environmentObject(settings)
                .environmentObject(updater)
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

    func windowWillClose(_ notification: Notification) {
        appearanceObserver = nil
        window?.contentView = nil
        window = nil
    }
}
