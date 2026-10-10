import AppKit
import Testing
@testable import CopyShot

@Suite("Capture mode routing")
@MainActor
struct CapturePipelineTests {
    @Test("The latest capture reports recognition activity before starting its worker")
    func recognitionActivity() throws {
        let image = try #require(Self.makeImage())
        let latest = UUID()
        var events: [String] = []
        let pipeline = CapturePipeline(isLatest: { $0 == latest }, cancellableRecognizers: [
            .latex: { _, _, _ in events.append("worker") }
        ], onRecognitionStarted: { mode in events.append(mode.rawValue) }, deliver: { _, _ in })
        pipeline.completeCapture(image: image, screen: nil, mode: .latex, requestID: UUID())
        pipeline.completeCapture(image: nil, screen: nil, mode: .latex, requestID: latest)
        #expect(events.isEmpty)
        pipeline.completeCapture(image: image, screen: nil, mode: .latex, requestID: latest)
        #expect(events == [CaptureMode.latex.rawValue, "worker"])
    }

    @Test("Replacing recognition cancels its work and still delivers the latest capture")
    func replacementCancelsRecognition() throws {
        let image = try #require(Self.makeImage())
        var latest = UUID()
        var tokens: [RecognitionCancellation] = []
        var completions: [@MainActor (Result<CaptureResult, Error>) -> Void] = []
        var delivered: [String] = []
        let pipeline = CapturePipeline(isLatest: { $0 == latest }, cancellableRecognizers: [
            .standardOCR: { _, token, completion in
                tokens.append(token)
                completions.append(completion)
            }
        ], deliver: { outcome, _ in
            if case .result(.standardText(let text)) = outcome { delivered.append(text) }
        })
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: latest)
        latest = UUID()
        pipeline.cancelRecognition()
        #expect(tokens[0].isCancelled)
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: latest)
        completions[0](.success(.standardText("old")))
        completions[1](.success(.standardText("new")))
        #expect(!tokens[1].isCancelled)
        #expect(delivered == ["new"])
    }

    @Test("An empty table has no clipboard content")
    func emptyTable() {
        #expect(CaptureResult.table(CapturedTable(rows: [["", " "]])).isEmpty)
    }

    @Test("Each descriptor dispatches to its registered recognizer")
    func routesAllModes() throws {
        let image = try #require(Self.makeImage())
        let requestID = UUID()
        var dispatched: [CaptureMode] = []
        var delivered: [CaptureMode] = []
        let recognizers = Dictionary(uniqueKeysWithValues: CaptureModeDescriptor.available.map { descriptor in
            (descriptor.id, { (_: CGImage, completion: @escaping @MainActor (Result<CaptureResult, Error>) -> Void) in
                dispatched.append(descriptor.id)
                completion(.success(.latex(formula: descriptor.title)))
            } as CapturePipeline.Recognizer)
        })
        let pipeline = CapturePipeline(isLatest: { $0 == requestID }, recognizers: recognizers) { outcome, _ in
            if case .result(let result) = outcome, case .latex(let title, _) = result,
                let mode = CaptureModeDescriptor.available.first(where: { $0.title == title })?.id {
                delivered.append(mode)
            }
        }

        for descriptor in CaptureModeDescriptor.available {
            pipeline.completeCapture(image: image, screen: nil, mode: descriptor.id, requestID: requestID)
        }
        #expect(dispatched == CaptureModeDescriptor.available.map(\.id))
        #expect(delivered == dispatched)
    }

    @Test("An older completion cannot replace the latest result")
    func olderCompletionIsIgnored() throws {
        let image = try #require(Self.makeImage())
        let first = UUID()
        let second = UUID()
        var latest = first
        var pending: [@MainActor (Result<CaptureResult, Error>) -> Void] = []
        var delivered: [String] = []
        let pipeline = CapturePipeline(
            isLatest: { $0 == latest },
            recognizers: [.standardOCR: { _, completion in pending.append(completion) }],
            deliver: { outcome, _ in
                if case .result(.standardText(let text)) = outcome { delivered.append(text) }
            }
        )
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: first)
        latest = second
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: second)
        #expect(pending.count == 2)
        pending[1](.success(.standardText("new")))
        pending[0](.success(.standardText("old")))
        #expect(delivered == ["new"])
    }

    @Test("A stale capture never starts recognition or reports cancellation")
    func staleCaptureIsIgnored() throws {
        let image = try #require(Self.makeImage())
        var recognitionCount = 0
        var deliveryCount = 0
        let pipeline = CapturePipeline(
            isLatest: { _ in false },
            recognizers: [.standardOCR: { _, _ in recognitionCount += 1 }],
            deliver: { _, _ in deliveryCount += 1 }
        )
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: UUID())
        pipeline.completeCapture(image: nil, screen: nil, mode: .standardOCR, requestID: UUID())
        #expect(recognitionCount == 0)
        #expect(deliveryCount == 0)
    }

    private static func makeImage() -> CGImage? {
        CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
}
