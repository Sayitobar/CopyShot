import AppKit
import Vision

enum BarcodeRecognitionService {
    private static let worker = RecognitionWorker(queue: DispatchQueue(label: "CopyShot.Barcodes", qos: .userInitiated))
    private static let prewarmCoalescer = PrewarmCoalescer<Bool>()
    private static func makeSyntheticImage() -> CGImage? {
        CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 16 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }

    /// Runs and discards a lightweight synthetic-image request to prewarm Vision barcode detection.
    static func prewarm(completion: @escaping (Bool) -> Void = { _ in }) {
        prewarmCoalescer.run(key: true, start: { done in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    guard let image = makeSyntheticImage() else { done(false); return }
                    let request = VNDetectBarcodesRequest()
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    do {
                        try handler.perform([request])
                        _ = request.results
                        done(true)
                    } catch {
                        #if DEBUG
                        debugPrint("[BarcodeRecognitionService] Prewarm error: \(error.localizedDescription)")
                        #endif
                        done(false)
                    }
                }
            }
        }, completion: completion)
    }

    static func recognize(_ image: CGImage, cancellation: RecognitionCancellation = RecognitionCancellation(),
                          completion: @escaping (Result<[DetectedBarcode], Error>) -> Void) {
        worker.submit(cancellation: cancellation) {
            let request = VNDetectBarcodesRequest()
            cancellation.onCancel { [weak request] in request?.cancel() }
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try cancellation.checkCancellation()
                try handler.perform([request])
                try cancellation.checkCancellation()
                let codes = (request.results ?? []).compactMap { observation -> DetectedBarcode? in
                    guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                    return DetectedBarcode(payload: payload, symbology: observation.symbology.rawValue)
                }
                DispatchQueue.main.async {
                    guard !cancellation.isCancelled else { return }
                    completion(.success(codes))
                }
            } catch {
                DispatchQueue.main.async {
                    guard !cancellation.isCancelled else { return }
                    completion(.failure(error))
                }
            }
        }
    }
}
