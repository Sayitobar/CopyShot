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

    struct TextSegment {
        let text: String
        let bounds: CGRect
    }
    
    // An enum to represent the possible outcomes.
    enum OCRResult {
        case success(String)
        case failure(Error)
    }
    
    static func performOCR(on image: CGImage, completion: @escaping (OCRResult) -> Void) {
        let settings = SettingsManager.shared
        let recognitionLevel: VNRequestTextRecognitionLevel = settings.recognitionLevel == .accurate ? .accurate : .fast
        let usesLanguageCorrection = settings.usesLanguageCorrection
        let recognitionLanguages = settings.recognitionLanguages

        DispatchQueue.global(qos: .userInitiated).async {
            guard let processedImage = preprocessImage(image) else {
                let error = NSError(domain: "OCRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image processing failed."])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = recognitionLanguages
            let requestHandler = VNImageRequestHandler(cgImage: processedImage, options: [:])
            do {
                try requestHandler.perform([request])
                let observations = request.results ?? []
                let segments = observations.compactMap { observation -> TextSegment? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return TextSegment(text: candidate.string, bounds: observation.boundingBox)
                }
                let recognizedText = assembleText(from: segments)
                DispatchQueue.main.async { completion(.success(recognizedText)) }
            } catch {
                debugPrint("OCR Request Handler Error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
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
            let matchingLine = lines.indices
                .filter { index in
                    let anchor = lines[index].anchor
                    let overlap = max(0, min(anchor.maxY, segment.bounds.maxY) - max(anchor.minY, segment.bounds.minY))
                    let smallerHeight = min(anchor.height, segment.bounds.height)
                    let centerDistance = abs(anchor.midY - segment.bounds.midY)
                    return overlap >= smallerHeight * 0.5 && centerDistance <= smallerHeight
                }
                .min { left, right in
                    abs(lines[left].anchor.midY - segment.bounds.midY) < abs(lines[right].anchor.midY - segment.bounds.midY)
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
