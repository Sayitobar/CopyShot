import Darwin
import Foundation
import OSLog
import Sparkle

/// Fixed events and typed fields keep user content out of persistent diagnostics.
enum DiagnosticEvent: String, Sendable {
    case appStarted = "app_started", appTerminated = "app_terminated"
    case captureStarted = "capture_started", captureCancelled = "capture_cancelled"
    case capturePermissionFailed = "capture_permission_failed", captureStateMissing = "capture_state_missing"
    case captureDisplayMissing = "capture_display_missing", screenshotFailed = "screenshot_failed"
    case captureEmpty = "capture_empty", captureFailed = "capture_failed", captureSucceeded = "capture_succeeded"
    case prewarmFailed = "prewarm_failed", hotkeyRegistrationFailed = "hotkey_registration_failed"
    case hotkeyEventFailed = "hotkey_event_failed", launchAtLoginFailed = "launch_at_login_failed"
    case actionStarted = "action_started", actionSucceeded = "action_succeeded"
    case actionCancelled = "action_cancelled", actionFailed = "action_failed"
    case scriptTimedOut = "script_timed_out", translationTimedOut = "translation_timed_out"
    case modelDownloadStarted = "model_download_started", modelDownloadSucceeded = "model_download_succeeded"
    case modelDownloadCancelled = "model_download_cancelled", modelDownloadFailed = "model_download_failed"
    case customCatalogInvalid = "custom_catalog_invalid", updateFailed = "update_failed"

    var level: String {
        if rawValue.hasSuffix("failed") || rawValue.hasSuffix("missing") { return "error" }
        if self == .scriptTimedOut || self == .translationTimedOut || self == .customCatalogInvalid { return "warning" }
        return "info"
    }
}

enum DiagnosticActionKind: String, Sendable {
    case builtIn = "built_in", script, url, translation

    init(_ operation: ActionOperation) {
        switch operation {
        case .translate: self = .translation
        case .custom(let descriptor): self = descriptor.isScript ? .script : .url
        default: self = .builtIn
        }
    }
}

/// Serial background I/O; file locking also protects concurrent app instances.
/// This intentionally accepts no free-form messages, titles, paths, or payloads.
final class DiagnosticLog: @unchecked Sendable {
    static let maximumBytes = 1_048_576
    static var applicationDataDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CopyShot", isDirectory: true)
    }
    static let shared: DiagnosticLog = {
        let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-show-settings")
        return DiagnosticLog(fileURL: isTest ? nil : applicationDataDirectory?.appendingPathComponent("diagnostics.log"))
    }()

    private let fileURL: URL?
    private let byteLimit: Int
    private let queue = DispatchQueue(label: "CopyShot.diagnostics", qos: .utility)
    private let session = UUID().uuidString
    private let systemLog = Logger(subsystem: "com.sayitobar.CopyShot", category: "diagnostics")
    private var reportedWriteFailure = false

    init(fileURL: URL?, byteLimit: Int = maximumBytes) {
        self.fileURL = fileURL
        self.byteLimit = max(1, min(byteLimit, Self.maximumBytes))
    }

    func record(_ event: DiagnosticEvent, mode: CaptureMode? = nil, action: DiagnosticActionKind? = nil,
                error: Error? = nil, code: Int? = nil, count: Int? = nil) {
        guard fileURL != nil else { return }
        // Never retain NSError/userInfo: descriptions, domains and underlying errors
        // can contain captured text, script stderr, URLs or personal file paths.
        let safeError = error.map { value -> (String, Int) in
            let error = value as NSError
            let domains: Set<String> = [NSCocoaErrorDomain, NSURLErrorDomain, NSOSStatusErrorDomain,
                "SCStreamErrorDomain", "com.apple.ScreenCaptureKit.SCStreamErrorDomain", "com.apple.Vision",
                "VNErrorDomain", "CopyShot.Translation", SUSparkleErrorDomain]
            return (domains.contains(error.domain) ? error.domain : "other", error.code)
        }
        let rawMode = mode?.rawValue
        let time = Date()
        queue.async { [self] in
            var entry: [String: Any] = ["timestamp": time.ISO8601Format(), "event": event.rawValue,
                                       "level": event.level, "session": session]
            if let rawMode { entry["mode"] = rawMode }
            if let action { entry["action"] = action.rawValue }
            if let safeError { entry["errorDomain"] = safeError.0; entry["errorCode"] = safeError.1 }
            if let code { entry["errorCode"] = code }
            if let count { entry["count"] = count }
            if event == .appStarted {
                entry["version"] = Self.safeVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"))
                entry["build"] = Self.safeVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion"))
                let version = ProcessInfo.processInfo.operatingSystemVersion
                entry["macOS"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
                #if arch(arm64)
                entry["architecture"] = "arm64"
                #else
                entry["architecture"] = "x86_64"
                #endif
            }
            do {
                var bytes = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
                bytes.append(10)
                try append(bytes)
                reportedWriteFailure = false
            } catch {
                // Logging must never change an operation's result or recurse into itself.
                if !reportedWriteFailure { systemLog.error("Could not write local diagnostics.") }
                reportedWriteFailure = true
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    /// A bounded best-effort drain for normal app termination, never ordinary capture.
    func flushOnTermination() {
        let completed = DispatchSemaphore(value: 0)
        queue.async { completed.signal() }
        _ = completed.wait(timeout: .now() + 0.25)
    }

    private static func safeVersion(_ value: Any?) -> String {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 64,
              value.allSatisfy({ $0.isASCII && ($0.isNumber || ".-+".contains($0)) }) else { return "unknown" }
        return value
    }

    private func append(_ record: Data) throws {
        guard let fileURL, record.count <= byteLimit else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = Darwin.open(fileURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        defer { try? handle.close() }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { _ = flock(descriptor, LOCK_UN) }
        guard fchmod(descriptor, 0o600) == 0 else { throw POSIXError(.EIO) }
        let length = try handle.seekToEnd()
        var endsWithNewline = length == 0
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            endsWithNewline = try handle.read(upToCount: 1)?.first == 10
        }
        if length <= UInt64(byteLimit - record.count), endsWithNewline {
            try handle.seekToEnd()
            try handle.write(contentsOf: record)
            return
        }
        // Read only a bounded suffix, even if a user replaced the log with a huge file.
        // Leave one quarter of the capacity for future appends. This avoids
        // rewriting a nearly full 1 MiB file for every subsequent event.
        let retainedCapacity = min(byteLimit - record.count, byteLimit * 3 / 4)
        let keptBytes = min(length, UInt64(retainedCapacity))
        let offset = length - keptBytes
        var startsAtBoundary = offset == 0
        if offset > 0 {
            try handle.seek(toOffset: offset - 1)
            startsAtBoundary = try handle.read(upToCount: 1)?.first == 10
        }
        try handle.seek(toOffset: offset)
        var tail = try handle.read(upToCount: Int(keptBytes)) ?? Data()
        if !startsAtBoundary {
            if let newline = tail.firstIndex(of: 10) { tail = Data(tail.suffix(from: tail.index(after: newline))) }
            else { tail.removeAll() }
        }
        if tail.last != 10 {
            if let newline = tail.lastIndex(of: 10) { tail = Data(tail.prefix(through: newline)) }
            else { tail.removeAll() }
        }
        if String(data: tail, encoding: .utf8) == nil { tail.removeAll() }
        tail.append(record)
        // Reuse the locked inode rather than replacing it under another writer's lock.
        try handle.seek(toOffset: 0)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: tail)
    }
}
