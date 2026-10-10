import CryptoKit
import Foundation
import Testing
@testable import CopyShot

@Suite("MFR model installation")
@MainActor
struct MFRModelDownloadTests {
    @Test("All files are verified before a complete model becomes available")
    func verifiedInstallation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = MFRModelManager(directory: fixture.destination, files: fixture.files,
                                      downloader: FixtureDownloader(contents: fixture.contents))
        #expect(manager.state == .notInstalled)
        #expect(await manager.startDownload().value)
        #expect(manager.state == .installed)
        for file in fixture.files {
            #expect(try Data(contentsOf: fixture.destination.appendingPathComponent(file.name)) == fixture.contents[file.name])
        }
    }

    @Test("Corrupt downloads cannot replace an existing incomplete installation")
    func rejectsCorruption() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        let existing = fixture.destination.appendingPathComponent("encoder_model.onnx")
        try Data("previous".utf8).write(to: existing)
        var corrupt = fixture.contents
        // Keep the same byte count so this exercises SHA-256, not only the size check.
        corrupt["decoder_model.onnx"] = Data("badcode".utf8)
        let manager = MFRModelManager(directory: fixture.destination, files: fixture.files,
                                      downloader: FixtureDownloader(contents: corrupt))
        #expect(!(await manager.startDownload().value))
        guard case .failed = manager.state else { Issue.record("Expected a checksum failure"); return }
        #expect(try Data(contentsOf: existing) == Data("previous".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("decoder_model.onnx").path))
    }

    @Test("Repeated requests share one download and cancellation leaves no installed model")
    func coalescingAndCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let downloader = HeldDownloader()
        let manager = MFRModelManager(directory: fixture.destination, files: fixture.files, downloader: downloader)
        let first = manager.startDownload()
        let second = manager.startDownload()
        await downloader.waitUntilStarted()
        manager.cancelDownload()
        await downloader.finish()
        #expect(!(await first.value))
        #expect(!(await second.value))
        #expect(await downloader.requestCount == 1)
        #expect(manager.state == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
    }

    @Test("A cancelled download can be retried successfully")
    func retryAfterCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = MFRModelManager(directory: fixture.destination, files: fixture.files,
                                      downloader: FixtureDownloader(contents: fixture.contents))
        let cancelled = manager.startDownload()
        manager.cancelDownload()
        #expect(!(await cancelled.value))
        #expect(await manager.startDownload().value)
        #expect(manager.state == .installed)
    }

    private struct Fixture {
        let root: URL
        let destination: URL
        let contents: [String: Data]
        let files: [MFRModelFile]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            destination = root.appendingPathComponent("MFR-1.5")
            contents = ["encoder_model.onnx": Data("encoder".utf8),
                        "decoder_model.onnx": Data("decoder".utf8),
                        "tokenizer.json": Data("tokenizer".utf8)]
            files = contents.sorted { $0.key < $1.key }.map { name, data in
                MFRModelFile(name: name, bytes: Int64(data.count),
                             sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private struct FixtureDownloader: MFRDownloading {
    let contents: [String: Data]

    func download(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let data = contents[url.lastPathComponent]!
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        progress(Int64(data.count))
        return file
    }
}

private actor HeldDownloader: MFRDownloading {
    private(set) var requestCount = 0
    private var started: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<URL, Error>?

    func waitUntilStarted() async {
        if requestCount > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func download(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        requestCount += 1
        started?.resume()
        started = nil
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish() {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}
