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
    
    // An enum to represent the possible outcomes.
    enum OCRResult {
        case success(String)
        case failure(Error)
    }
    
    // The primary function of the service.
    // In OCRService.swift

    static func performOCR(on image: CGImage, completion: @escaping (OCRResult) -> Void) {
        
        guard let processedImage = preprocessImage(image) else {
            completion(.failure(NSError(domain: "OCRService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image processing failed."])))
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: processedImage, options: [:])
        
        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                print("OCR Error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async { completion(.success("")) }
                return
            }
            
            // --- INTELLIGENT STRING BUILDING LOGIC ---
            
            var recognizedText = ""
            var lastY: CGFloat? = nil
            
            // Vision observations are not always in logical reading order.
            // We should sort them from top-to-bottom, then left-to-right.
            let sortedObservations = observations.sorted {
                // Primary sort by Y-coordinate (top-to-bottom)
                // Note: Vision's Y-coordinate is from the bottom-left, so we compare the max Y.
                if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.02 { // Tolerance for slight misalignment
                    return $0.boundingBox.maxY > $1.boundingBox.maxY
                }
                // Secondary sort by X-coordinate (left-to-right) for items on the same line
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            
            for observation in sortedObservations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                
                let currentY = observation.boundingBox.midY
                
                if let previousY = lastY {
                    // Check if the vertical distance is large enough to be a new line.
                    // The threshold (0.02) may need tuning, but it's a good start.
                    // It represents 2% of the image's height.
                    if abs(currentY - previousY) > 0.02 {
                        recognizedText += "\n"
                    } else {
                        // It's on the same line, add a space.
                        recognizedText += " "
                    }
                }
                
                recognizedText += topCandidate.string
                lastY = currentY
            }
            
            DispatchQueue.main.async {
                completion(.success(recognizedText))
            }
        }
        
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false  // Keep this on for natural language
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("OCR Request Handler Error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
    
    private static func preprocessImage(_ originalImage: CGImage) -> CGImage? {
        // Create a Core Image context
        let context = CIContext(options: nil)
        
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
              let processedCGImage = context.createCGImage(finalImage, from: finalImage.extent) else {
            return originalImage // If processing fails, return the original
        }
        
        return processedCGImage
    }
}
