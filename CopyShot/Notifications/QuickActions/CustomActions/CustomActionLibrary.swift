import AppKit
import Combine
import Foundation

struct CustomActionCatalog {
    let actions: [CustomActionDescriptor]
    let diagnostics: [CustomActionDiagnostic]
    let managementActions: [CustomActionDescriptor]
    let registry: ActionRegistry

    func action(id: String) -> CustomActionDescriptor? { actions.first { $0.metadata.id == id } }
}

/// App services observe snapshots; Codable defaults never depend on filesystem discovery.
@MainActor
final class CustomActionLibrary: ObservableObject {
    static let shared: CustomActionLibrary = {
        let environment = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-show-settings"),
           let suite = environment["COPYSHOT_UI_TEST_SETTINGS_SUITE"], suite.hasPrefix("CopyShot.UITests."),
           let defaults = UserDefaults(suiteName: suite) {
            // UI tests use a private directory and never inspect the user's installed scripts.
            let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try? FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            return CustomActionLibrary(directory: fixtureDirectory, defaults: defaults)
        }
        return CustomActionLibrary()
    }()

    @Published private(set) var catalog = CustomActionCatalog(actions: [], diagnostics: [], managementActions: [], registry: ActionRegistry())
    private(set) var urlActions: [CustomURLAction] = []
    private(set) var directory: URL?

    private let defaults: UserDefaults
    private let hasHandler: (URL) -> Bool
    private var scripts: [ScriptAction] = []
    private var scriptDiagnostics: [CustomActionDiagnostic] = []
    private var storageDiagnostic: String?
    private var watcher: ScriptDirectoryWatcher?
    private var activationObserver: AnyCancellable?
    private var started = false
    private var reloadGeneration = UUID()
    private static let storageKey = "customURLActions"
    private struct Storage: Codable { let version: Int; let actions: [CustomURLAction] }

    init(directory: URL? = nil, defaults: UserDefaults = .standard, hasHandler: @escaping (URL) -> Bool = ActionURLHelper.hasHandler) {
        self.directory = directory
        self.defaults = defaults
        self.hasHandler = hasHandler
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                let stored = try JSONDecoder().decode(Storage.self, from: data)
                guard stored.version == 1 else { throw CustomActionError.invalidMetadata("The saved URL actions use a newer format.") }
                urlActions = stored.actions
            } catch {
                DiagnosticLog.shared.record(.customCatalogInvalid, error: error)
                storageDiagnostic = "Could not load saved URL actions: \(error.localizedDescription)"
            }
        }
        publishSnapshot()
    }

    func start() {
        guard !started else { return }
        started = true
        watcher = ScriptDirectoryWatcher { [weak self] in
            Task { @MainActor [weak self] in guard let self, self.started else { return }; await self.reload() }
        }
        activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, self.started else { return }; await self.reload() }
        }
        Task { [weak self] in await self?.reload() }
    }

    func stop() {
        started = false
        reloadGeneration = UUID()
        watcher = nil
        activationObserver = nil
    }

    func reload() async {
        let generation = UUID()
        reloadGeneration = generation
        let suppliedDirectory = directory
        let result: (URL?, ScriptActionScan) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let root = try suppliedDirectory ?? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    continuation.resume(returning: (root, ScriptActionDiscovery.scan(directory: root)))
                } catch {
                    continuation.resume(returning: (nil, .init(diagnostics: [.init(fileURL: nil, message: error.localizedDescription)])))
                }
            }
        }
        guard generation == reloadGeneration, !Task.isCancelled else { return }
        directory = result.0
        scripts = result.1.actions
        scriptDiagnostics = result.1.diagnostics
        if !scriptDiagnostics.isEmpty {
            DiagnosticLog.shared.record(.customCatalogInvalid, count: scriptDiagnostics.count)
        }
        publishSnapshot()
        if let directory { watcher?.watch(directory: directory, files: result.1.files) }
    }

    func saveURLAction(_ action: CustomURLAction) throws {
        if let storageDiagnostic { throw CustomActionError.invalidMetadata(storageDiagnostic) }
        var saved = action
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        try saved.validate(hasHandler: hasHandler)
        var updated = urlActions
        if let index = updated.firstIndex(where: { $0.id == saved.id }) { updated[index] = saved } else { updated.append(saved) }
        defaults.set(try JSONEncoder().encode(Storage(version: 1, actions: updated)), forKey: Self.storageKey)
        urlActions = updated
        publishSnapshot()
    }

    func deleteURLAction(id: UUID) {
        guard storageDiagnostic == nil else { return }
        let updated = urlActions.filter { $0.id != id }
        guard let data = try? JSONEncoder().encode(Storage(version: 1, actions: updated)) else { return }
        defaults.set(data, forKey: Self.storageKey)
        urlActions = updated
        publishSnapshot()
    }

    func deleteScript(_ script: ScriptAction, moveToTrash: (ScriptAction) async throws -> Void = CustomActionLibrary.moveScriptToTrash) async throws {
        guard scripts.contains(script), script.fileURL.deletingLastPathComponent().standardizedFileURL == directory?.standardizedFileURL else {
            throw CustomActionError.scriptChanged
        }
        try await Self.validateRemoval(script)
        try await moveToTrash(script)
        await reload()
    }

    private static func moveScriptToTrash(_ script: ScriptAction) async throws {
        let url = script.fileURL
        // Finder can recycle writable files directly. A user selection grants access
        // when the Application Scripts directory is read-only to our sandbox.
        do { try await recycle(url); return } catch {
            guard FileManager.default.fileExists(atPath: url.path) else { throw error }
        }
        let folder = url.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Allow Removal"
        panel.message = "Choose CopyShot’s actions folder to allow moving \(url.lastPathComponent) to Trash."
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else { panel.begin { continuation.resume(returning: $0) } }
        }
        guard response == .OK, let selected = panel.url else { throw CancellationError() }
        guard selected.standardizedFileURL == folder.standardizedFileURL else {
            throw CustomActionError.invalidMetadata("Choose the actions folder shown in the removal prompt.")
        }
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        // The permission dialog may stay open while an editor replaces the file.
        try await validateRemoval(script)
        try await recycle(url)
    }

    private static func validateRemoval(_ script: ScriptAction) async throws {
        try await Task.detached(priority: .utility) {
            let values = try script.fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let source = try? String(contentsOf: script.fileURL, encoding: .utf8),
                  ScriptAction.digest(source) == script.revision else { throw CustomActionError.scriptChanged }
        }.value
        try Task.checkCancellation()
    }

    private static func recycle(_ url: URL) async throws {
        let moved = try await NSWorkspace.shared.recycle([url])
        guard moved[url] != nil else { throw CocoaError(.fileWriteUnknown) }
    }

    func openActionsFolder() async {
        if directory == nil { await reload() }
        if let directory { NSWorkspace.shared.open(directory) }
    }

    static func openStarterScripts() -> Bool {
        guard let url = Bundle.main.url(forResource: "strip_line_numbers", withExtension: "sh", subdirectory: "StarterActions")
                ?? Bundle.main.url(forResource: "strip_line_numbers", withExtension: "sh") else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    private func publishSnapshot() {
        var entries = scripts.map(CustomActionDescriptor.script)
        var managed = entries
        var errors = scriptDiagnostics
        if let storageDiagnostic { errors.append(.init(fileURL: nil, message: storageDiagnostic)) }
        var seen = Set<UUID>()
        for link in urlActions {
            do {
                guard seen.insert(link.id).inserted else { throw CustomActionError.invalidMetadata("Duplicate saved URL action ID.") }
                // Keep authored definitions repairable when a destination app disappears.
                managed.append(.url(link))
                try link.validate(hasHandler: hasHandler)
                entries.append(.url(link))
            } catch { errors.append(.init(fileURL: nil, message: "\(link.title): \(error.localizedDescription)")) }
        }
        managed.sort {
            let comparison = $0.metadata.title.localizedStandardCompare($1.metadata.title)
            return comparison == .orderedSame ? $0.metadata.id < $1.metadata.id : comparison == .orderedAscending
        }
        guard entries != catalog.actions || errors != catalog.diagnostics || managed != catalog.managementActions else { return }
        catalog = CustomActionCatalog(actions: entries, diagnostics: errors, managementActions: managed,
                                      registry: ActionRegistry(providers: [BuiltInActionProvider(), CustomActionProvider(actions: entries)]))
    }
}
