import AppKit
import Testing
@testable import CopyShot

@Suite("Capture to OCR delivery")
@MainActor
struct CapturePipelineTests {
    @Test("An older OCR completion cannot replace the latest delivered text")
    func olderOCRCompletionIsIgnored() throws {
        let image = try #require(Self.makeImage())
        let first = UUID()
        let second = UUID()
        var latest = first
        var pending: [@MainActor (OCRService.OCRResult) -> Void] = []
        var delivered: [String] = []
        let pipeline = CapturePipeline(
            isLatest: { $0 == latest },
            recognize: { _, completion in pending.append(completion) },
            deliver: { outcome, _ in
                if case .text(let text) = outcome { delivered.append(text) }
            }
        )

        pipeline.completeCapture(image: image, screen: nil, requestID: first)
        latest = second
        pipeline.completeCapture(image: image, screen: nil, requestID: second)
        #expect(pending.count == 2)

        pending[1](.success("new text"))
        pending[0](.success("old text"))
        #expect(delivered == ["new text"])
    }

    @Test("A stale capture result never starts OCR or shows cancellation")
    func staleCaptureIsIgnored() throws {
        let image = try #require(Self.makeImage())
        let current = UUID()
        var recognitionCount = 0
        var deliveryCount = 0
        let pipeline = CapturePipeline(
            isLatest: { $0 == current },
            recognize: { _, _ in recognitionCount += 1 },
            deliver: { _, _ in deliveryCount += 1 }
        )

        pipeline.completeCapture(image: image, screen: nil, requestID: UUID())
        pipeline.completeCapture(image: nil, screen: nil, requestID: UUID())
        #expect(recognitionCount == 0)
        #expect(deliveryCount == 0)
    }

    private static func makeImage() -> CGImage? {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}
