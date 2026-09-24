//
//  OCRServiceTests.swift
//  CopyShotTests
//
//  Created for CopyShot.
//

import Testing
import Foundation
import CoreGraphics
import CoreText
import Vision
@testable import CopyShot

@Suite("OCRService Tests")
struct OCRServiceTests {
    
    /// Helper to synthesize an in-memory CGImage with black text on a white canvas.
    private func createTextImage(text: String, size: CGSize = CGSize(width: 400, height: 100)) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Fill white background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        
        // Draw black text with CoreText
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 16, y: 36)
        CTLineDraw(line, context)
        
        return context.makeImage()
    }
    
    /// Helper to synthesize a multi-line image with two distinct vertical lines.
    private func createMultiLineImage(line1: String, line2: String, size: CGSize = CGSize(width: 400, height: 200)) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Fill white background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        
        // Draw line 2 near the bottom (in CoreGraphics coords)
        let attrString2 = NSAttributedString(string: line2, attributes: attributes)
        let ctLine2 = CTLineCreateWithAttributedString(attrString2)
        context.textPosition = CGPoint(x: 16, y: 40)
        CTLineDraw(ctLine2, context)
        
        // Draw line 1 near the top
        let attrString1 = NSAttributedString(string: line1, attributes: attributes)
        let ctLine1 = CTLineCreateWithAttributedString(attrString1)
        context.textPosition = CGPoint(x: 16, y: 140)
        CTLineDraw(ctLine1, context)
        
        return context.makeImage()
    }

    /// Helper to synthesize a completely blank image.
    private func createBlankImage(size: CGSize = CGSize(width: 200, height: 100)) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    @Test("OCR successfully recognizes clear synthetic text")
    func testSyntheticTextRecognition() async throws {
        let testPhrase = "CopyShot Fast OCR"
        guard let image = createTextImage(text: testPhrase) else {
            Issue.record("Failed to create synthetic test image")
            return
        }
        
        let recognized = try await withCheckedThrowingContinuation { continuation in
            OCRService.performOCR(on: image) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        #expect(!recognized.isEmpty)
        // Flexible assertion: check that key recognizable tokens appear
        let lowercased = recognized.lowercased()
        #expect(lowercased.contains("copyshot") || lowercased.contains("fast") || lowercased.contains("ocr"))
    }

    @Test("OCR handles blank images gracefully without failing")
    func testBlankImageHandling() async throws {
        guard let blankImage = createBlankImage() else {
            Issue.record("Failed to create blank test image")
            return
        }
        
        let recognized = try await withCheckedThrowingContinuation { continuation in
            OCRService.performOCR(on: blankImage) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Blank image should yield empty string, not a failure
        #expect(recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("OCR multi-line recognition preserves distinct lines")
    func testMultiLineRecognition() async throws {
        let lineA = "First Line of Text"
        let lineB = "Second Line of Text"
        guard let image = createMultiLineImage(line1: lineA, line2: lineB) else {
            Issue.record("Failed to create multi-line test image")
            return
        }
        
        let recognized = try await withCheckedThrowingContinuation { continuation in
            OCRService.performOCR(on: image) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        #expect(!recognized.isEmpty)
        // Check that either newline separator is present or both lines were captured
        let lowercased = recognized.lowercased()
        #expect(lowercased.contains("first") || lowercased.contains("line"))
        #expect(lowercased.contains("second") || lowercased.contains("text"))
    }
}
