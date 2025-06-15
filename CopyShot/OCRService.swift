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
    // It's async to avoid blocking the main thread during recognition.
    static func performOCR(on image: CGImage, completion: @escaping (OCRResult) -> Void) {
        // 1. Create a request handler for the image
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        
        // 2. Create the text recognition request
        let request = VNRecognizeTextRequest { (request, error) in
            // This completion block is called after the request is processed.
            
            if let error = error {
                print("OCR Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                // No text was found in the image. This is not an error, just an empty result.
                DispatchQueue.main.async {
                    completion(.success(""))
                }
                return
            }
            
            // 3. Extract and combine the recognized text
            let recognizedText = observations.compactMap { observation in
                // Get the top candidate for each recognized text block.
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n") // Join multi-line text with newlines
            
            DispatchQueue.main.async {
                completion(.success(recognizedText))
            }
        }
        
        // For now, we'll use the "fast" recognition mode.
        // In Phase 3, we can make this a user setting (.accurate).
        request.recognitionLevel = .fast
        
        // For now, we will let Vision automatically detect the language.
        // In Phase 3, we'll allow the user to specify languages here.
        // request.recognitionLanguages = ["en-US", "de-DE"]
        
        // 4. Perform the request on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("OCR Request Handler Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
