import SwiftUI

/// A Settings-owned sheet keeps selective reset separate from tab sizing probes.
struct SettingsResetSheet: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var updater: UpdaterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<SettingsResetPage> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Reset Settings", systemImage: "arrow.counterclockwise")
                .font(.system(size: 16, weight: .semibold))
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
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings-reset-cancel")
                Button("Reset Selected", role: .destructive) {
                    settings.reset(pages: selected)
                    if selected.contains(.general) {
                        updater.automaticallyChecksForUpdates = Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false
                    }
                    dismiss()
                }
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("settings-reset-confirm")
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}
