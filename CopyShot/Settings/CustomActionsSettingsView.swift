import AppKit
import SwiftUI

struct CustomActionsSettingsSection: View {
    @ObservedObject var library: CustomActionLibrary
    let mode: CaptureMode
    let isBaseline: Bool
    @Binding var isExpanded: Bool
    @Binding var editing: CustomURLAction?
    @State private var deleting: CustomURLAction?
    @State private var starterError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Custom Actions")
            HStack(spacing: 10) {
                Button { Task { await library.openActionsFolder() } } label: { Label("Open Actions Folder", systemImage: "folder") }
                    .accessibilityIdentifier("qa-open-actions-folder")
                Button {
                    if !CustomActionLibrary.openStarterScripts() { starterError = "The starter scripts could not be found in this build." }
                } label: { Label("Starter Scripts", systemImage: "doc.text") }
                    .accessibilityIdentifier("qa-starter-scripts")
                Spacer(minLength: 0)
                Button {
                    editing = CustomURLAction(supportedModes: [mode])
                    isExpanded = true
                } label: { Label("Add URL Action", systemImage: "plus") }
                    .accessibilityIdentifier("qa-add-url")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isExpanded && !isBaseline ? 90 : 0))
                    Text("Manage Actions")
                    Spacer()
                    if !isBaseline {
                        Text("\(library.catalog.managementActions.count) actions\(library.catalog.diagnostics.isEmpty ? "" : " · \(library.catalog.diagnostics.count) issues")")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("qa-custom-manage")

            if !isBaseline && isExpanded {
                managementContent
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .alert("Starter Scripts", isPresented: Binding(get: { starterError != nil }, set: { if !$0 { starterError = nil } })) {
            Button("OK") { starterError = nil }
        } message: { Text(starterError ?? "") }
        .alert("Delete URL Action?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { library.deleteURLAction(id: deleting.id); if editing?.id == deleting.id { editing = nil } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the URL action from every capture mode.") }
    }

    private var managementContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy executable .sh files into the actions folder in Finder. New actions start disabled; enable and reorder them in the mode list above. Scripts run only when selected and may access files or services outside CopyShot’s sandbox.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Starter Scripts opens the bundled examples. Copy them into the actions folder; if needed, use chmod +x with the script’s quoted path in Terminal. Script headers control title, modes, output, and wait time.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let editing {
                URLActionEditor(action: editing, save: { action in try library.saveURLAction(action); self.editing = nil }, cancel: { self.editing = nil })
                    .id(editing.id)
            }

            ForEach(library.catalog.managementActions, id: \.metadata.id) { action in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        ActionIconView(icon: action.metadata.icon, size: 14)
                        Text(action.metadata.title).font(.system(size: 11.5, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        switch action {
                        case .script(let script):
                            Button { NSWorkspace.shared.activateFileViewerSelecting([script.fileURL]) } label: { Image(systemName: "folder") }
                                .help("Reveal script in Finder")
                                .accessibilityIdentifier("qa-reveal-script-\(script.metadata.id)")
                        case .url(let link):
                            Button { editing = link } label: { Image(systemName: "pencil") }
                                .help("Edit URL action")
                                .accessibilityIdentifier("qa-edit-url-\(link.id.uuidString)")
                            Button { deleting = link } label: { Image(systemName: "trash") }
                                .help("Delete URL action")
                                .accessibilityIdentifier("qa-delete-url-\(link.id.uuidString)")
                        }
                    }
                    Text(action.isScript ? "Script" : "URL link")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider().opacity(0.3)
                }
                .buttonStyle(.plain)
            }
            ForEach(library.catalog.diagnostics) { diagnostic in
                VStack(alignment: .leading, spacing: 4) {
                    Label(diagnostic.fileURL?.lastPathComponent ?? "Custom Actions", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.orange)
                    Text(diagnostic.message).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let url = diagnostic.fileURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.plain)
                    }
                }
                .accessibilityIdentifier("qa-custom-diagnostic")
            }
        }
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
            Text("URL Action").font(.system(size: 12, weight: .semibold))
            TextField("Title", text: $draft.title).accessibilityIdentifier("qa-url-title")
            TextField("Description (optional)", text: $draft.description).accessibilityIdentifier("qa-url-description")
            HStack {
                Text("SF Symbol").foregroundStyle(.secondary)
                TextField("link", text: $draft.iconName).accessibilityIdentifier("qa-url-icon")
                ActionIconView(icon: .system(draft.iconName), size: 14)
            }
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
            TextField("https://example.com/?q={text}", text: $draft.template).accessibilityIdentifier("qa-url-template")
            Text("{text} and {encoded_text} insert the current captured text with URL encoding. Selecting this action sends that text to the destination.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let preview = try? ActionURLHelper.expand(draft.template, text: "Sample captured text") {
                Text("Preview: \(preview.absoluteString)").foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityIdentifier("qa-url-preview")
            }
            if let error { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("qa-url-error") }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).accessibilityIdentifier("qa-url-cancel")
                Button("Save") {
                    do { try save(draft) } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("qa-url-save")
            }
        }
        .font(.system(size: 11))
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
    }
}

struct CustomActionDetailsView: View {
    let descriptor: CustomActionDescriptor
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !descriptor.metadata.description.isEmpty { Text(descriptor.metadata.description) }
            if case .script(let script) = descriptor {
                Text(script.fileURL.lastPathComponent).font(.system(size: 11, design: .monospaced))
                Text("Input: current text via stdin · Output: \(script.output.rawValue) · Wait: \(script.timeout.formatted())s")
                Text("Edit the file’s @copyshot headers to customize this action.").foregroundStyle(.secondary)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([script.fileURL]) }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 11))
        .fixedSize(horizontal: false, vertical: true)
    }
}
