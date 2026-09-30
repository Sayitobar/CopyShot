import AppKit
import Vision

enum BarcodeRecognitionService {
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
