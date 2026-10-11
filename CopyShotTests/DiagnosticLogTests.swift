import XCTest
@testable import CopyShot

final class DiagnosticLogTests: XCTestCase {
    private func temporaryLog() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnostics \(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("diagnostics.log")
    }

    func testRollingLogRetainsNewestCompleteRecordsWithinByteLimit() async throws {
        let url = try temporaryLog()
        let log = DiagnosticLog(fileURL: url, byteLimit: 1024)
        for code in 0..<100 { log.record(.captureFailed, mode: .standardOCR, code: code) }
        await log.flush()
        let bytes = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(bytes.count, 1024)
        XCTAssertEqual(bytes.last, 10)
        let rows = try records(bytes)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertLessThan(rows.count, 100)
        XCTAssertEqual(rows.last?["errorCode"] as? Int, 99)
        XCTAssertEqual(rows.last?["mode"] as? String, "standardOCR")
        XCTAssertTrue(rows.allSatisfy { $0["event"] as? String == "capture_failed" })
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testConcurrentWritersPreserveAllRecords() async throws {
        let url = try temporaryLog()
        let first = DiagnosticLog(fileURL: url)
        let second = DiagnosticLog(fileURL: url)
        await withTaskGroup(of: Void.self) { group in
            for code in 0..<200 {
                group.addTask { (code.isMultiple(of: 2) ? first : second).record(.actionFailed, code: code) }
            }
        }
        await first.flush()
        await second.flush()
        let rows = try records(Data(contentsOf: url))
        XCTAssertEqual(rows.count, 200)
        XCTAssertEqual(Set(rows.compactMap { $0["errorCode"] as? Int }), Set(0..<200))
    }

    func testRestartPreservesPriorEntriesAndRepairsOversizedTail() async throws {
        let url = try temporaryLog()
        let first = DiagnosticLog(fileURL: url, byteLimit: 1024)
        first.record(.appStarted)
        await first.flush()
        let second = DiagnosticLog(fileURL: url, byteLimit: 1024)
        second.record(.appTerminated)
        await second.flush()
        XCTAssertEqual(try records(Data(contentsOf: url)).compactMap { $0["event"] as? String }, ["app_started", "app_terminated"])
        try Data(repeating: 0x61, count: 2048).write(to: url)
        second.record(.captureFailed, code: 7)
        await second.flush()
        let bytes = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(bytes.count, 1024)
        XCTAssertEqual(try records(bytes).count, 1)
        XCTAssertEqual(try records(bytes).last?["errorCode"] as? Int, 7)
    }

    func testErrorDetailsCannotPersistPersonalContent() async throws {
        let url = try temporaryLog()
        let log = DiagnosticLog(fileURL: url)
        let secret = "PRIVATE_CAPTURE_日本語 https://example.com/?secret /Users/person/private.sh"
        log.record(.actionFailed, error: NSError(domain: secret, code: 42, userInfo: [
            NSLocalizedDescriptionKey: secret, NSFilePathErrorKey: secret,
            NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: secret])
        ]))
        await log.flush()
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(secret))
        let row = try XCTUnwrap(try records(bytes).first)
        XCTAssertEqual(row["errorDomain"] as? String, "other")
        XCTAssertEqual(row["errorCode"] as? Int, 42)
        XCTAssertNil(row["message"])
    }

    func testRotationKeepsAnEntryStartingExactlyAtTheRetainedBoundary() async throws {
        let url = try temporaryLog()
        let probe = DiagnosticLog(fileURL: url)
        probe.record(.captureFailed, code: 1)
        await probe.flush()
        let rowBytes = try Data(contentsOf: url).count
        let log = DiagnosticLog(fileURL: url, byteLimit: rowBytes * 3)
        for code in 2...4 { log.record(.captureFailed, code: code) }
        await log.flush()
        XCTAssertEqual(try records(Data(contentsOf: url)).compactMap { $0["errorCode"] as? Int }, [2, 3, 4])
    }

    func testRestartDropsAnIncompleteFinalEntry() async throws {
        let url = try temporaryLog()
        let log = DiagnosticLog(fileURL: url)
        log.record(.captureStarted)
        await log.flush()
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"event\":\"partial".utf8))
        try handle.close()
        log.record(.captureFailed)
        await log.flush()
        XCTAssertEqual(try records(Data(contentsOf: url)).compactMap { $0["event"] as? String }, ["capture_started", "capture_failed"])
    }

    func testUnwritableDestinationAndSymlinkLeaveAppAndOtherFilesUnaffected() async throws {
        let url = try temporaryLog()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = url.deletingLastPathComponent().appendingPathComponent("private.txt")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let log = DiagnosticLog(fileURL: url)
        log.record(.appStarted)
        await log.flush()
        XCTAssertEqual(try Data(contentsOf: target), Data("untouched".utf8))
        let blocked = DiagnosticLog(fileURL: target.appendingPathComponent("diagnostics.log"))
        blocked.record(.captureFailed)
        await blocked.flush()
        XCTAssertEqual(try Data(contentsOf: target), Data("untouched".utf8))
    }

    private func records(_ data: Data) throws -> [[String: Any]] {
        try data.split(separator: 10).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }
}
