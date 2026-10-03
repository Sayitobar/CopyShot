//
//  OCRService.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import Foundation
import Vision
import AppKit // Needed for CGImage

class OCRService {
    private static let worker = RecognitionWorker(queue: DispatchQueue(label: "CopyShot.OCR", qos: .userInitiated))
    private static let prewarmCoalescer = PrewarmCoalescer<Configuration>()

    struct Configuration: Hashable {
        let level: Int
        let usesLanguageCorrection: Bool
        let languages: [String]

        init(settings: SettingsManager = .shared) {
            level = settings.recognitionLevel.rawValue
            usesLanguageCorrection = settings.usesLanguageCorrection
            languages = settings.recognitionLanguages
        }

        func apply(to request: VNRecognizeTextRequest) {
            request.recognitionLevel = level == RecognitionLevel.accurate.rawValue ? .accurate : .fast
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = languages
        }
    }

    struct TextSegment {
        let text: String
        let bounds: CGRect
    }
    
    // An enum to represent the possible outcomes.
    enum OCRResult {
        case success(String)
        case failure(Error)
    }
    
    static func performOCR(on image: CGImage, cancellation: RecognitionCancellation = RecognitionCancellation(),
                           completion: @escaping (OCRResult) -> Void) {
        recognize(on: image, cancellation: cancellation, transform: assembleText) { result in
            switch result {
            case .success(let text): completion(.success(text))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

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

    /// Runs and discards a lightweight synthetic-image request to prewarm Vision text recognition.
    static func prewarm(configuration: Configuration = Configuration(), completion: @escaping (Bool) -> Void = { _ in }) {
        prewarmCoalescer.run(key: configuration, start: { done in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    guard let image = makeSyntheticImage(),
                          let processed = preprocessImage(image) ?? makeSyntheticImage() else { done(false); return }
                    let request = VNRecognizeTextRequest()
                    configuration.apply(to: request)
                    let handler = VNImageRequestHandler(cgImage: processed, options: [:])
                    do {
                        try handler.perform([request])
                        _ = request.results
                        done(true)
                    } catch {
                        #if DEBUG
                        debugPrint("[OCRService] Prewarm error: \(error.localizedDescription)")
                        #endif
                        done(false)
                    }
                }
            }
        }, completion: completion)
    }

    static func performOCRSegments(on image: CGImage,
                                   completion: @escaping (Result<[TextSegment], Error>) -> Void) {
        recognize(on: image, cancellation: RecognitionCancellation(), transform: { $0 }, completion: completion)
    }

    static func recognize<Output>(on image: CGImage, cancellation: RecognitionCancellation,
                                  transform: @escaping ([TextSegment]) -> Output,
                                  completion: @escaping (Result<Output, Error>) -> Void) {
        let configuration = Configuration()

        worker.submit(cancellation: cancellation) {
            guard let processedImage = preprocessImage(image) else {
                let error = NSError(domain: "OCRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image processing failed."])
                DispatchQueue.main.async {
                    guard !cancellation.isCancelled else { return }
                    completion(.failure(error))
                }
                return
            }

            let request = VNRecognizeTextRequest()
            configuration.apply(to: request)
            cancellation.onCancel { [weak request] in request?.cancel() }
            let requestHandler = VNImageRequestHandler(cgImage: processedImage, options: [:])
            do {
                try cancellation.checkCancellation()
                try requestHandler.perform([request])
                try cancellation.checkCancellation()
                let observations = request.results ?? []
                let segments = observations.compactMap { observation -> TextSegment? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return TextSegment(text: candidate.string, bounds: observation.boundingBox)
                }
                let output = transform(segments)
                DispatchQueue.main.async {
                    guard !cancellation.isCancelled else { return }
                    completion(.success(output))
                }
            } catch {
                guard !cancellation.isCancelled else { return }
                debugPrint("OCR Request Handler Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    guard !cancellation.isCancelled else { return }
                    completion(.failure(error))
                }
            }
        }
    }

    static func assembleText(from segments: [TextSegment]) -> String {
        struct Line {
            let anchor: CGRect
            var segments: [TextSegment]
        }

        let topFirst = segments.sorted {
            if $0.bounds.maxY != $1.bounds.maxY { return $0.bounds.maxY > $1.bounds.maxY }
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            return $0.text < $1.text
        }
        var lines: [Line] = []
        for segment in topFirst {
            var matchingLine: Int?
            var nearestDistance = CGFloat.infinity
            for index in lines.indices {
                let anchor = lines[index].anchor
                let overlap = max(0, min(anchor.maxY, segment.bounds.maxY) - max(anchor.minY, segment.bounds.minY))
                let smallerHeight = min(anchor.height, segment.bounds.height)
                let centerDistance = abs(anchor.midY - segment.bounds.midY)
                if overlap >= smallerHeight * 0.5 && centerDistance <= smallerHeight && centerDistance < nearestDistance {
                    matchingLine = index
                    nearestDistance = centerDistance
                }
            }
            if let index = matchingLine {
                lines[index].segments.append(segment)
            } else {
                lines.append(Line(anchor: segment.bounds, segments: [segment]))
            }
        }

        return lines.sorted {
            if $0.anchor.maxY != $1.anchor.maxY { return $0.anchor.maxY > $1.anchor.maxY }
            return $0.anchor.minX < $1.anchor.minX
        }
        .map { line in
            line.segments.sorted {
                if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
                return $0.text < $1.text
            }
            .map(\.text)
            .joined(separator: " ")
        }
        .joined(separator: "\n")
    }
    
    private static let ciContext = CIContext(options: nil)

    private static func preprocessImage(_ originalImage: CGImage) -> CGImage? {
        // Create a CIImage from the CGImage
        let ciImage = CIImage(cgImage: originalImage)
        
        // Create a grayscale filter
        guard let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono") else { return originalImage }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Create a contrast filter
        guard let contrastFilter = CIFilter(name: "CIColorControls"),
              let outputImage = grayscaleFilter.outputImage else { return originalImage }
        
        contrastFilter.setValue(outputImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.5, forKey: kCIInputContrastKey) // Increase contrast by 50%
        
        // Get the final processed image
        guard let finalImage = contrastFilter.outputImage,
              let processedCGImage = ciContext.createCGImage(finalImage, from: finalImage.extent) else {
            return originalImage // If processing fails, return the original
        }
        
        return processedCGImage
    }
}
