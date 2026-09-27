import AppKit

/// Keeps asynchronous OCR results tied to the capture that produced them.
@MainActor
final class CapturePipeline {
    enum Outcome {
        case cancelled
        case noText
        case text(String)
        case failed(Error)
    }

    private let isLatest: (UUID) -> Bool
    private let recognize: (CGImage, @escaping @MainActor (OCRService.OCRResult) -> Void) -> Void
    private let deliver: (Outcome, NSScreen?) -> Void

    init(
        isLatest: @escaping (UUID) -> Bool,
        recognize: @escaping (CGImage, @escaping @MainActor (OCRService.OCRResult) -> Void) -> Void,
        deliver: @escaping (Outcome, NSScreen?) -> Void
    ) {
        self.isLatest = isLatest
        self.recognize = recognize
        self.deliver = deliver
    }

    func completeCapture(image: CGImage?, screen: NSScreen?, requestID: UUID) {
        guard isLatest(requestID) else { return }
        guard let image else {
            deliver(.cancelled, screen)
            return
        }

        recognize(image) { [weak self] result in
            guard let self, self.isLatest(requestID) else { return }
            switch result {
            case .success(let text):
                self.deliver(text.isEmpty ? .noText : .text(text), screen)
            case .failure(let error):
                self.deliver(.failed(error), screen)
            }
        }
    }
}
