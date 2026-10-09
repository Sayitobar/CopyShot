import AppKit
import SwiftUI

struct CustomActionsSettingsSection: View {
    @ObservedObject var library: CustomActionLibrary
    let mode: CaptureMode
    let isBaseline: Bool
    @Binding var editing: CustomURLAction?
    @State private var expandedActionID: String?
    @State private var infoExpanded = false
    @State private var deleting: CustomActionDescriptor?
    @State private var isRemoving = false
    @State private var removalError: String?
    @State private var starterError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Custom Actions")
            HStack(spacing: 10) {
                Button {
                    Task { await library.openActionsFolder() }
                } label: { Label("Open Actions Folder", systemImage: "folder") }
                .accessibilityIdentifier("qa-open-actions-folder")
                Button {
                    if !CustomActionLibrary.openStarterScripts() { starterError = "The starter scripts could not be found in this build." }
                } label: { Label("Starter Scripts", systemImage: "doc.text") }
                .accessibilityIdentifier("qa-starter-scripts")
                Spacer(minLength: 0)
                Button {
                    editing = CustomURLAction(supportedModes: [mode])
                } label: { Label("Add URL Action", systemImage: "plus") }
                .accessibilityIdentifier("qa-add-url")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 11.5))

            if !isBaseline {
                if let editing {
                    URLActionEditor(action: editing, save: { action in
                        try library.saveURLAction(action)
                        self.editing = nil
                    }, cancel: { self.editing = nil })
                    .id(editing.id)
                    .padding(10)
                    .customActionSurface()
                }
                if library.catalog.managementActions.isEmpty {
                    Text("No custom actions yet. Add a URL action or install a script.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(library.catalog.managementActions.enumerated()), id: \.element.metadata.id) { index, action in
                            CustomActionManagementRow(
                                action: action,
                                isExpanded: expandedActionID == action.metadata.id,
                                showsDivider: index < library.catalog.managementActions.count - 1,
                                expand: {
                                    withAnimation(DisclosureChevron.animation) {
                                        expandedActionID = expandedActionID == action.metadata.id ? nil : action.metadata.id
                                    }
                                },
                                edit: { editing = $0 },
                                remove: { deleting = action }
                            )
                            .disabled(isRemoving)
                        }
                    }
                    .customActionSurface()
                    .accessibilityIdentifier("qa-custom-manage")
                }
                ForEach(library.catalog.diagnostics) { diagnostic in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(diagnostic.fileURL?.lastPathComponent ?? "Custom Actions", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.orange)
                        Text(diagnostic.message).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if let url = diagnostic.fileURL {
                            SettingsIconButton(title: "Reveal in Finder", icon: "doc.text") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    }
                    .padding(10)
                    .customActionSurface()
                    .accessibilityIdentifier("qa-custom-diagnostic")
                }
            }
            installationHelp
        }
        .alert("Starter Scripts", isPresented: Binding(get: { starterError != nil }, set: { if !$0 { starterError = nil } })) {
            Button("OK") { starterError = nil }
        } message: { Text(starterError ?? "") }
        .alert("Remove Custom Action?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(deleting?.isScript == true ? "Move to Trash" : "Delete", role: .destructive) {
                if let action = deleting {
                    deleting = nil
                    remove(action)
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            if case .script(let script) = deleting {
                Text("Move \(script.fileURL.lastPathComponent) to Trash? This removes the action from every capture mode. You can restore its file from Trash.")
            } else { Text("Delete this URL action from every capture mode?") }
        }
        .alert("Couldn’t Remove Action", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK") { removalError = nil }
        } message: { Text(removalError ?? "") }
        .onReceive(library.$catalog) { catalog in
            if let expandedActionID, !catalog.managementActions.contains(where: { $0.metadata.id == expandedActionID }) {
                self.expandedActionID = nil
            }
        }
    }

    private var installationHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(DisclosureChevron.animation) { infoExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Using Custom Actions")
                    Spacer(minLength: 0)
                    DisclosureChevron(isExpanded: infoExpanded && !isBaseline)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("qa-custom-help")
            if infoExpanded && !isBaseline {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Copy executable .sh files into the actions folder in Finder. New actions start disabled; enable and reorder them in the mode list above. Scripts run only when selected and may access files or services outside CopyShot’s sandbox.")
                    Text("Starter Scripts opens the bundled examples. Copy them into the actions folder; if needed, use chmod +x with the script’s quoted path in Terminal. Script headers control title, modes, output, and wait time.")
                    Text("Removing a script moves its file to Trash. macOS may ask you to select the actions folder to allow removal.")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("qa-custom-installation-help")
            }
        }
        .padding(10)
        .customActionSurface()
    }

    private func remove(_ action: CustomActionDescriptor) {
        isRemoving = true
        Task {
            defer { isRemoving = false }
            do {
                switch action {
                case .script(let script): try await library.deleteScript(script)
                case .url(let link):
                    library.deleteURLAction(id: link.id)
                    if editing?.id == link.id { editing = nil }
                }
                if expandedActionID == action.metadata.id { expandedActionID = nil }
            } catch is CancellationError {
                // Cancelling the native folder chooser leaves the action intact.
            } catch { removalError = error.localizedDescription }
        }
    }
}

private struct CustomActionManagementRow: View {
    let action: CustomActionDescriptor
    let isExpanded: Bool
    let showsDivider: Bool
    let expand: () -> Void
    let edit: (CustomURLAction) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ActionSettingsIconBadge(icon: action.metadata.icon)
                Text(action.metadata.title).font(.system(size: 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                SettingsIconButton(title: isExpanded ? "Hide Details" : "Show Details", icon: "chevron.down", isExpanded: isExpanded, action: expand)
                    .accessibilityIdentifier("qa-custom-expand-\(action.metadata.id)")
                switch action {
                case .script(let script):
                    SettingsIconButton(title: "Reveal script in Finder", icon: "doc.text") {
                        NSWorkspace.shared.activateFileViewerSelecting([script.fileURL])
                    }
                    .accessibilityIdentifier("qa-reveal-script-\(script.metadata.id)")
                case .url(let link):
                    SettingsIconButton(title: "Edit URL action", icon: "pencil") { edit(link) }
                        .accessibilityIdentifier("qa-edit-url-\(link.id.uuidString)")
                }
                SettingsIconButton(title: action.isScript ? "Move script to Trash" : "Delete URL action", icon: "trash", isDestructive: true, action: remove)
                    .accessibilityIdentifier(action.isScript ? "qa-delete-script-\(action.metadata.id)" : "qa-delete-url-\(urlID)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            if isExpanded {
                CustomActionDetailsView(descriptor: action)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
                    .accessibilityIdentifier("qa-custom-details-\(action.metadata.id)")
            }
            if showsDivider { Divider().opacity(0.35).padding(.horizontal, 10) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qa-custom-row-\(action.metadata.id)")
    }

    private var urlID: String {
        if case .url(let link) = action { return link.id.uuidString }
        return ""
    }
}

private struct URLActionEditor: View {
    @State private var draft: CustomURLAction
    @State private var error: String?
    let save: (CustomURLAction) throws -> Void
    let cancel: () -> Void

    init(action: CustomURLAction, save: @escaping (CustomURLAction) throws -> Void, cancel: @escaping () -> Void) {
        _draft = State(initialValue: action)
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL Action").font(.system(size: 12.5, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Title").foregroundStyle(.secondary)
                    TextField("Title", text: $draft.title).accessibilityIdentifier("qa-url-title")
                }
                GridRow {
                    Text("Description").foregroundStyle(.secondary)
                    TextField("Optional", text: $draft.description)
                        .accessibilityLabel("Description")
                        .accessibilityIdentifier("qa-url-description")
                }
                GridRow {
                    Text("SF Symbol").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("link", text: $draft.iconName).accessibilityIdentifier("qa-url-icon")
                        ActionSettingsIconBadge(icon: .system(draft.iconName))
                    }
                }
                GridRow {
                    Text("Modes").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(CaptureModeDescriptor.available) { descriptor in
                            Toggle(descriptor.title, isOn: Binding(
                                get: { draft.supportedModes.contains(descriptor.id) },
                                set: { if $0 { draft.supportedModes.insert(descriptor.id) } else { draft.supportedModes.remove(descriptor.id) } }
                            ))
                            .toggleStyle(.checkbox).controlSize(.mini)
                            .accessibilityIdentifier("qa-url-mode-\(descriptor.id.rawValue)")
                        }
                    }
                }
                GridRow {
                    Text("URL").foregroundStyle(.secondary)
                    TextField("https://example.com/?q={text}", text: $draft.template).accessibilityIdentifier("qa-url-template")
                }
            }
            Text("{text} and {encoded_text} insert the current captured text with URL encoding. Selecting this action sends that text to the destination.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let preview = try? ActionURLHelper.expand(draft.template, text: "Sample captured text") {
                Text("Preview: \(preview.absoluteString)").font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityIdentifier("qa-url-preview")
            }
            if let error { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("qa-url-error") }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.bordered).accessibilityIdentifier("qa-url-cancel")
                Button("Save") {
                    do { try save(draft) } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("qa-url-save")
            }
        }
        .font(.system(size: 11.5))
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
    }
}

struct CustomActionDetailsView: View {
    let descriptor: CustomActionDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !descriptor.metadata.description.isEmpty {
                Text(descriptor.metadata.description).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Text(descriptor.isScript ? "Shell Script" : "URL Template")
                }
                GridRow {
                    Text("Modes").foregroundStyle(.secondary)
                    Text(CaptureModeDescriptor.available.filter { descriptor.metadata.supportedModes.contains($0.id) }.map(\.title).joined(separator: " · "))
                }
                switch descriptor {
                case .script(let script):
                    GridRow {
                        Text("File").foregroundStyle(.secondary)
                        Text(script.fileURL.lastPathComponent).font(.system(size: 11, design: .monospaced))
                    }
                    GridRow {
                        Text("Input").foregroundStyle(.secondary)
                        Text("Current text via stdin")
                    }
                    GridRow {
                        Text("Output").foregroundStyle(.secondary)
                        Text(script.output.rawValue)
                    }
                    GridRow {
                        Text("Wait").foregroundStyle(.secondary)
                        Text("\(script.timeout.formatted())s")
                    }
                case .url(let link):
                    GridRow {
                        Text("URL").foregroundStyle(.secondary)
                        Text(link.template).textSelection(.enabled)
                    }
                }
            }
            if descriptor.isScript {
                Text("Edit the file’s @copyshot headers to customize this action.").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11.5))
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ActionSettingsIconBadge: View {
    let icon: ActionIcon
    var isEnabled = true

    var body: some View {
        ActionIconView(icon: icon, size: 14, isHovered: isEnabled, accentColor: .primary)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(isEnabled ? 0.08 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct CustomActionIndicator: View {
    var body: some View {
        Image(systemName: "puzzlepiece.extension")
            .font(.system(size: 9.5))
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Custom action")
            .help("Custom action")
    }
}

private extension View {
    func customActionSurface() -> some View {
        background(Color(NSColor.controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
    }
}
