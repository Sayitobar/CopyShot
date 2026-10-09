import CryptoKit
import Foundation

enum ScriptOutput: String, Equatable {
    case copy
    case openURL = "open-url"
    case none
}

struct ScriptAction: Equatable {
    let metadata: ActionMetadata
    let fileURL: URL
    let output: ScriptOutput
    let timeout: TimeInterval
    let revision: String

    static func parse(source: String, url: URL) throws -> Self {
        let known = Set(["id", "title", "description", "icon", "modes", "output", "timeout"])
        var headers: [String: String] = [:]
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("#") else { break }
            let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard comment.hasPrefix("@copyshot.") else { continue }
            let header = comment.dropFirst("@copyshot.".count)
            let pieces = header.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let key = pieces.first.map(String.init), known.contains(key) else { continue }
            let value = pieces.count == 2 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
            guard headers[key] == nil else { throw CustomActionError.invalidMetadata("Duplicate @copyshot.\(key) header.") }
            guard !value.isEmpty else { throw CustomActionError.invalidMetadata("@copyshot.\(key) needs a value.") }
            headers[key] = value
        }
        let modes: Set<CaptureMode>
        if let raw = headers["modes"] {
            let values = raw.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard !values.isEmpty, values.allSatisfy({ CaptureMode(rawValue: $0) != nil }) else {
                throw CustomActionError.invalidMetadata("Modes must be standardOCR, qrBarcode, latex, or table, separated by commas.")
            }
            modes = Set(values.compactMap(CaptureMode.init(rawValue:)))
        } else { modes = [.standardOCR] }
        guard let output = ScriptOutput(rawValue: headers["output"] ?? "copy") else {
            throw CustomActionError.invalidMetadata("Output must be copy, open-url, or none.")
        }
        let timeout = headers["timeout"].flatMap(Double.init) ?? (headers["timeout"] == nil ? 30 : .nan)
        guard timeout.isFinite, timeout > 0 else { throw CustomActionError.invalidMetadata("Timeout must be a positive number of seconds.") }
        let title = headers["title"] ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let metadata = ActionMetadata(id: "custom.script.\(headers["id"] ?? url.lastPathComponent)", title: title,
                                      description: headers["description"] ?? "", icon: .system(headers["icon"] ?? "terminal"),
                                      hasSubActions: false, hasParameters: true, supportedModes: modes)
        return .init(metadata: metadata, fileURL: url, output: output, timeout: timeout, revision: digest(source))
    }

    static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CustomURLAction: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var description: String = ""
    var iconName: String = "link"
    var supportedModes: Set<CaptureMode> = [.standardOCR]
    var template: String = ""

    var actionID: String { "custom.url.\(id.uuidString)" }
    var metadata: ActionMetadata {
        .init(id: actionID, title: title, description: description, icon: .system(iconName),
              hasSubActions: false, hasParameters: true, supportedModes: supportedModes)
    }

    func validate(hasHandler: (URL) -> Bool = ActionURLHelper.hasHandler) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !supportedModes.isEmpty else {
            throw CustomActionError.invalidMetadata("Enter a title and select at least one capture mode.")
        }
        _ = try ActionURLHelper.expand(template, text: "Sample captured text", hasHandler: hasHandler)
    }
}

enum CustomActionDescriptor: Equatable {
    case script(ScriptAction)
    case url(CustomURLAction)

    var metadata: ActionMetadata {
        switch self { case .script(let script): script.metadata; case .url(let link): link.metadata }
    }
    var isScript: Bool { if case .script = self { return true }; return false }
}

enum CustomActionError: LocalizedError {
    case invalidMetadata(String), invalidURL(String), scriptChanged, busy, inputLimit, outputLimit
    case invalidOutput, timedOut, failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMetadata(let reason), .invalidURL(let reason), .failed(let reason): reason
        case .scriptChanged: "This script changed or was removed. Wait for the actions list to reload and try again."
        case .busy: "This script is still running, or four script runs are already active. Stopping the wait does not terminate a script."
        case .inputLimit: "Script input exceeds the 4 MiB limit."
        case .outputLimit: "Script output exceeds the 4 MiB limit."
        case .invalidOutput: "The script output is not valid UTF-8 text."
        case .timedOut: "Stopped waiting for the script. It may still be running; late results will be ignored."
        }
    }
}

struct CustomActionProvider: ActionProvider {
    let actions: [CustomActionDescriptor]
    var definitions: [ActionDefinition] {
        actions.map { descriptor in
            .init(metadata: descriptor.metadata, defaultEnabledModes: [], makeAction: { _, _ in
                QuickAction(id: descriptor.metadata.id, title: descriptor.metadata.title, icon: descriptor.metadata.icon,
                            shortcutNumber: nil, operation: .custom(descriptor), helpText: descriptor.metadata.description)
            })
        }
    }
}
