import Foundation

struct CustomActionDiagnostic: Equatable, Identifiable {
    let fileURL: URL?
    let message: String
    var id: String { "\(fileURL?.path ?? "folder"): \(message)" }
}

struct ScriptActionScan {
    var actions: [ScriptAction] = []
    var diagnostics: [CustomActionDiagnostic] = []
    var files: [URL] = []
}

enum ScriptActionDiscovery {
    static func scan(directory: URL) -> ScriptActionScan {
        var result = ScriptActionScan()
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for url in urls {
                result.files.append(url)
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, url.pathExtension == "sh" else {
                        throw CustomActionError.invalidMetadata("Only regular .sh files directly in the actions folder are supported; symbolic links are not supported.")
                    }
                    guard FileManager.default.isExecutableFile(atPath: url.path) else {
                        throw CustomActionError.invalidMetadata("Make this script executable in Terminal: chmod +x followed by its quoted path.")
                    }
                    let source = try String(contentsOf: url, encoding: .utf8)
                    result.actions.append(try ScriptAction.parse(source: source, url: url))
                } catch { result.diagnostics.append(.init(fileURL: url, message: error.localizedDescription)) }
            }
            let duplicateIDs = Set(Dictionary(grouping: result.actions, by: { $0.metadata.id }).filter { $0.value.count > 1 }.keys)
            for action in result.actions where duplicateIDs.contains(action.metadata.id) {
                result.diagnostics.append(.init(fileURL: action.fileURL, message: "Duplicate action ID. Give each script a unique @copyshot.id."))
            }
            result.actions.removeAll { duplicateIDs.contains($0.metadata.id) }
        } catch { result.diagnostics.append(.init(fileURL: directory, message: "Could not read the actions folder: \(error.localizedDescription)")) }
        return result
    }
}
