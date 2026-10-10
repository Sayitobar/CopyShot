import AppKit

struct DetectedBarcode: Equatable {
    let payload: String
    let symbology: String
}

struct CapturedTable: Equatable {
    let rows: [[String]]

    var tabSeparatedText: String {
        rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }
}

enum CaptureResult: Equatable {
    case standardText(String)
    case barcodes([DetectedBarcode])
    case latex(formula: String, statusNote: String? = nil)
    case table(CapturedTable)

    var isEmpty: Bool {
        switch self {
        case .standardText(let text): text.isEmpty
        case .latex(let formula, _): formula.isEmpty
        case .barcodes(let codes): codes.isEmpty
        case .table(let table): table.rows.allSatisfy { row in
            row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        }
    }
}

/// Associates asynchronous recognition with the capture request and its selected mode.
@MainActor
final class CapturePipeline {
    enum Outcome {
        case cancelled
        case noContent(CaptureMode)
        case result(CaptureResult)
        case failed(CaptureMode, Error)
    }

    typealias Recognizer = (CGImage, @escaping @MainActor (Result<CaptureResult, Error>) -> Void) -> Void
    typealias CancellableRecognizer = (CGImage, RecognitionCancellation, @escaping @MainActor (Result<CaptureResult, Error>) -> Void) -> Void

    private let isLatest: (UUID) -> Bool
    private let recognizers: [CaptureMode: CancellableRecognizer]
    private let deliver: (Outcome, NSScreen?) -> Void
    private let onRecognitionStarted: (CaptureMode) -> Void
    private var recognition: RecognitionCancellation?

    convenience init(isLatest: @escaping (UUID) -> Bool,
         recognizers: [CaptureMode: Recognizer],
         deliver: @escaping (Outcome, NSScreen?) -> Void) {
        self.init(isLatest: isLatest, cancellableRecognizers: recognizers.mapValues { recognize in
            { image, _, completion in recognize(image, completion) }
        }, deliver: deliver)
    }

    init(isLatest: @escaping (UUID) -> Bool,
         cancellableRecognizers: [CaptureMode: CancellableRecognizer],
         onRecognitionStarted: @escaping (CaptureMode) -> Void = { _ in },
         deliver: @escaping (Outcome, NSScreen?) -> Void) {
        self.isLatest = isLatest
        self.recognizers = cancellableRecognizers
        self.onRecognitionStarted = onRecognitionStarted
        self.deliver = deliver
    }

    func cancelRecognition() {
        recognition?.cancel()
        recognition = nil
    }

    func completeCapture(image: CGImage?, screen: NSScreen?, mode: CaptureMode, requestID: UUID) {
        guard isLatest(requestID) else { return }
        cancelRecognition()
        guard let image else {
            deliver(.cancelled, screen)
            return
        }
        guard let recognizer = recognizers[mode] else {
            deliver(.failed(mode, NSError(domain: "CapturePipeline", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "No recognizer for \(mode.rawValue)."])), screen)
            return
        }
        let cancellation = RecognitionCancellation()
        recognition = cancellation
        onRecognitionStarted(mode)
        recognizer(image, cancellation) { [weak self] result in
            guard let self, !cancellation.isCancelled, self.isLatest(requestID) else { return }
            if self.recognition === cancellation { self.recognition = nil }
            switch result {
            case .success(let content):
                self.deliver(content.isEmpty ? .noContent(mode) : .result(content), screen)
            case .failure(let error):
                self.deliver(.failed(mode, error), screen)
            }
        }
    }
}
