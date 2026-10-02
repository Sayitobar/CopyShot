import AppKit
import Vision

enum BarcodeRecognitionService {
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
    static func prewarm() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = makeSyntheticImage() else { return }
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                _ = request.results
            } catch {
                #if DEBUG
                debugPrint("[BarcodeRecognitionService] Prewarm error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    static func recognize(_ image: CGImage, completion: @escaping (Result<[DetectedBarcode], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
                let codes = (request.results ?? []).compactMap { observation -> DetectedBarcode? in
                    guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                    return DetectedBarcode(payload: payload, symbology: observation.symbology.rawValue)
                }
                DispatchQueue.main.async { completion(.success(codes)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
