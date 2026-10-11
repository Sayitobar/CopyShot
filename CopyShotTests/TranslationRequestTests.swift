import XCTest
#if canImport(Translation)
import Translation
#endif
@testable import CopyShot

@MainActor
final class TranslationRequestTests: XCTestCase {
    func testAlreadyCancelledCallerDoesNotWaitForFrameworkTranslation() async {
        let task = Task { try await TranslationService.shared.translate(text: "Hallo", targetLanguageCode: "en") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    #if canImport(Translation)
    func testRepeatedLanguagePairCreatesADistinctConfiguration() {
        if #available(macOS 15.0, *) {
            var sequence = TranslationConfigurationSequence()
            let source = Locale.Language(identifier: "de"), target = Locale.Language(identifier: "en")
            let first = sequence.next(source: source, target: target)
            let second = sequence.next(source: source, target: target)
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(second.source, source)
            XCTAssertEqual(second.target, target)
        }
    }
    #endif

    func testDeadlineRemainsActiveAfterTheSessionStartsAndCompletesExactlyOnce() async throws {
        let lifetime = TranslationRequestLifetime(timeout: 0.02)
        var results: [Result<TranslationResult, Error>] = []
        var cancelled = 0
        let id = UUID()
        lifetime.start(id: id, cancelOperation: { cancelled += 1 }, completion: { results.append($0) })
        XCTAssertTrue(lifetime.isCurrent(id)) // The session has started; it still owns its deadline.
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(lifetime.isCurrent(id))
        lifetime.finish(id: id, result: .success(result))
        XCTAssertEqual(results.count, 1)
    }

    func testSupersessionAndCancellationSuppressLateCompletionWithoutCancellingNewerRequest() {
        let lifetime = TranslationRequestLifetime(timeout: 120)
        let old = UUID(), new = UUID()
        var oldResults: [Result<TranslationResult, Error>] = []
        var newResults: [Result<TranslationResult, Error>] = []
        var cancelled = 0
        lifetime.start(id: old, cancelOperation: { cancelled += 1 }, completion: { oldResults.append($0) })
        lifetime.start(id: new, cancelOperation: { cancelled += 1 }, completion: { newResults.append($0) })
        XCTAssertEqual(oldResults.count, 1)
        XCTAssertEqual(cancelled, 1)
        lifetime.cancel(id: old)
        lifetime.finish(id: old, result: .success(result))
        XCTAssertTrue(lifetime.isCurrent(new))
        XCTAssertTrue(newResults.isEmpty)
        lifetime.cancel(id: new)
        XCTAssertEqual(newResults.count, 1)
        XCTAssertEqual(cancelled, 2)
        if case .failure(let error) = newResults[0] { XCTAssertTrue(error is CancellationError) }
        else { XCTFail("Cancelled translation completed successfully") }
        lifetime.finish(id: new, result: .success(result))
        XCTAssertEqual(newResults.count, 1)
    }

    private var result: TranslationResult {
        .init(originalText: "Hallo", translatedText: "Hello", sourceLanguageCode: "de", sourceLanguageName: "German", targetLanguageCode: "en", targetLanguageName: "English")
    }
}
