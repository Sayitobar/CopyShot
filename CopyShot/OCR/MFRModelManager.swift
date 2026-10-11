import Combine
import CryptoKit
import Foundation

struct MFRModelFile: Sendable {
    let name: String
    let bytes: Int64
    let sha256: String
}

enum MFRModelState: Equatable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case installed
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying: true
        default: false
        }
    }
}

/// A single pinned set of data files, shared by installation and recognition.
enum MFRModelResources {
    static let revision = "1cef9f0bdcd6a4c63df7de1311fb0894593340cc"
    static let files = [
        MFRModelFile(name: "encoder_model.onnx", bytes: 87_510_770,
                     sha256: "080a3f660f08bc9ebcacdd96e34be6b6400f8c7e62d7cd0dd8251badc37f610b"),
        MFRModelFile(name: "decoder_model.onnx", bytes: 32_026_253,
                     sha256: "917deb98e91a0453c5f234f58a0f32f9fb037de8527c7eb4ed394daf9e692f2a"),
        MFRModelFile(name: "tokenizer.json", bytes: 113_168,
                     sha256: "4ffbeb2143e6a38324bb6111b7a8109530d38a076a8439aa5777535f0a32758a")
    ]
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyShot/MFR-1.5", isDirectory: true)
    }

    static var recognitionDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["COPYSHOT_MFR_MODEL_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("MFR-1.5", isDirectory: true),
           isComplete(bundled) { return bundled }
        return applicationSupport
    }

    static func isComplete(_ directory: URL, files: [MFRModelFile] = files) -> Bool {
        files.allSatisfy { file in
            let values = try? directory.appendingPathComponent(file.name).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && Int64(values?.fileSize ?? -1) == file.bytes
        }
    }
}

protocol MFRDownloading: Sendable {
    /// Returns a caller-owned temporary file. Only model URLs, never captured images, are supplied.
    func download(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL
}

@MainActor
final class MFRModelManager: ObservableObject {
    static let shared = MFRModelManager()
    @Published private(set) var state: MFRModelState
    let directory: URL
    private let files: [MFRModelFile]
    private let downloader: any MFRDownloading
    private var operation: Task<Bool, Never>?
    private var generation: UUID?

    init(directory: URL = MFRModelResources.recognitionDirectory,
         files: [MFRModelFile] = MFRModelResources.files,
         downloader: any MFRDownloading = MFRURLSessionDownloader()) {
        self.directory = directory
        self.files = files
        self.downloader = downloader
        state = MFRModelResources.isComplete(directory, files: files) ? .installed : .notInstalled
    }

    var isAvailable: Bool {
        MFRModelResources.isComplete(directory, files: files)
    }

    func refreshAvailability() {
        guard !state.isBusy else { return }
        if isAvailable { state = .installed }
        else if case .failed = state { return }
        else { state = .notInstalled }
    }

    @discardableResult
    func startDownload() -> Task<Bool, Never> {
        if let operation { return operation }
        if MFRModelResources.isComplete(directory, files: files) {
            state = .installed
            return Task { true }
        }
        let id = UUID()
        DiagnosticLog.shared.record(.modelDownloadStarted)
        generation = id
        let total = files.reduce(Int64(0)) { $0 + $1.bytes }
        state = .downloading(received: 0, total: total)
        let task = Task { [self] in
            let staging = directory.deletingLastPathComponent().appendingPathComponent(".MFR-\(id).download", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: staging)
                if generation == id { generation = nil; operation = nil }
            }
            do {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                var completedBytes: Int64 = 0
                for file in files {
                    try Task.checkCancellation()
                    let base = completedBytes
                    let url = URL(string: "https://huggingface.co/breezedeus/pix2text-mfr-1.5/resolve/\(MFRModelResources.revision)/\(file.name)")!
                    let temporary = try await downloader.download(url) { [weak self] bytes in
                        Task { @MainActor in
                            guard let self, self.generation == id,
                                  case .downloading(let received, _) = self.state else { return }
                            self.state = .downloading(received: max(received, base + min(bytes, file.bytes)), total: total)
                        }
                    }
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try Task.checkCancellation()
                    try FileManager.default.moveItem(at: temporary, to: staging.appendingPathComponent(file.name))
                    completedBytes += file.bytes
                    state = .downloading(received: completedBytes, total: total)
                }
                state = .verifying
                // Hashing 120 MB runs off the main actor; cancellation is also checked while hashing.
                let verification = Task.detached(priority: .userInitiated) { [files] in
                    try MFRModelInstaller.verify(staging, files: files)
                }
                try await withTaskCancellationHandler {
                    try await verification.value
                } onCancel: { verification.cancel() }
                try Task.checkCancellation()
                guard generation == id else { return false }
                try MFRModelInstaller.install(staging, at: directory)
                state = .installed
                DiagnosticLog.shared.record(.modelDownloadSucceeded)
                return true
            } catch {
                DiagnosticLog.shared.record(error is CancellationError ? .modelDownloadCancelled : .modelDownloadFailed, error: error)
                if generation == id {
                    state = error is CancellationError ? .notInstalled : .failed(error.localizedDescription)
                }
                return false
            }
        }
        operation = task
        return task
    }

    func cancelDownload() {
        generation = nil
        operation?.cancel()
        operation = nil
        state = MFRModelResources.isComplete(directory, files: files) ? .installed : .notInstalled
    }
}

enum MFRModelInstaller {
    static func verify(_ directory: URL, files: [MFRModelFile]) throws {
        for file in files {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(file.name)
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(file.bytes) else {
                throw MFRDownloadError.invalidFile(file.name)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == file.sha256 else { throw MFRDownloadError.invalidFile(file.name) }
        }
    }

    static func install(_ staging: URL, at destination: URL) throws {
        let manager = FileManager.default
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".MFR-\(UUID()).backup")
        let existed = manager.fileExists(atPath: destination.path)
        if existed { try manager.moveItem(at: destination, to: backup) }
        do {
            try manager.moveItem(at: staging, to: destination)
        } catch {
            if existed { try? manager.moveItem(at: backup, to: destination) }
            throw error
        }
        if existed { try? manager.removeItem(at: backup) }
    }
}

enum MFRDownloadError: LocalizedError {
    case invalidFile(String)
    case httpStatus(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidFile(let name): "The downloaded \(name) could not be verified. Please try again."
        case .httpStatus(let status): "The model server returned HTTP \(status). Please try again."
        case .cancelled: "The model download was cancelled."
        }
    }
}

struct MFRURLSessionDownloader: MFRDownloading {
    func download(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let operation = MFRFileDownload(progress: progress)
        return try await withTaskCancellationHandler {
            try await operation.start(url)
        } onCancel: { operation.cancel() }
    }
}

/// Moves URLSession's ephemeral download before its delegate callback returns.
private final class MFRFileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false

    init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }

    func start(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 1_200
            config.httpCookieStorage = nil
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            self.task = task
            lock.unlock()
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
                throw MFRDownloadError.httpStatus((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("MFR-\(UUID()).download")
            try FileManager.default.moveItem(at: location, to: file)
            finish(.success(file))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure((error as NSError).code == NSURLErrorCancelled ? CancellationError() : error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let session = session
        self.session = nil
        task = nil
        lock.unlock()
        if let continuation { continuation.resume(with: result) }
        else if case .success(let file) = result { try? FileManager.default.removeItem(at: file) }
        session?.finishTasksAndInvalidate()
    }
}
