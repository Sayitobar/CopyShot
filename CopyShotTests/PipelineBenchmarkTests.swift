//
//  PipelineBenchmarkTests.swift
//  CopyShotTests
//
//  Created for CopyShot.
//

import Testing
import Foundation
import AppKit
import CoreGraphics
import CoreText
import CoreImage.CIFilterBuiltins
import Darwin
@testable import CopyShot

@Suite("Performance Benchmarks", .serialized)
@MainActor
struct PipelineBenchmarkTests {
    @Test("Cold/reused Vision requests and MFR session lifetime")
    func testRecognitionSessionLifetimeBenchmark() async throws {
        func footprintMB() -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
        }
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data("copyshot:benchmark".utf8)
        let qrOutput = try #require(qr.outputImage)
        let qrImage = try #require(CIContext().createCGImage(qrOutput.transformed(by: .init(scaleX: 12, y: 12)), from: qrOutput.extent.applying(.init(scaleX: 12, y: 12))))
        for run in 1...3 {
            let start = CFAbsoluteTimeGetCurrent()
            let result = await withCheckedContinuation { continuation in
                BarcodeRecognitionService.recognize(qrImage) { continuation.resume(returning: $0) }
            }
            #expect(try result.get().contains { $0.payload == "copyshot:benchmark" })
            NSLog("[Recognition benchmark] Barcode %d: %.1f ms, footprint %.1f MiB", run, (CFAbsoluteTimeGetCurrent() - start) * 1_000, footprintMB())
        }
        let textImage = try #require(createRetinaCaptureImage(lines: ["x² + y² = z²"], pointSize: .init(width: 320, height: 70), fontSize: 32))
        for run in 1...3 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try await runPipeline(on: textImage)
            NSLog("[Recognition benchmark] OCR %d: %.1f ms, footprint %.1f MiB", run, (CFAbsoluteTimeGetCurrent() - start) * 1_000, footprintMB())
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyShot/MFR-1.5")
        let path = ProcessInfo.processInfo.environment["COPYSHOT_MFR_MODEL_DIR"] ?? directory.path
        guard FileManager.default.fileExists(atPath: path + "/encoder_model.onnx") else {
            NSLog("[Recognition benchmark] MFR unavailable at %@", path)
            return
        }
        setenv("COPYSHOT_MFR_MODEL_DIR", path, 1)
        func measureFormula(_ service: FormulaRecognitionService, label: String) async throws {
            let start = CFAbsoluteTimeGetCurrent()
            let result = await withCheckedContinuation { continuation in
                service.recognize(textImage) { continuation.resume(returning: $0) }
            }
            let formula = try result.get()
            #expect(!formula.isEmpty)
            NSLog("[Recognition benchmark] %@: %.1f ms, footprint %.1f MiB; %@", label, (CFAbsoluteTimeGetCurrent() - start) * 1_000, footprintMB(), formula.formula)
        }
        var cached: FormulaRecognitionService? = FormulaRecognitionService()
        for run in 1...3 { try await measureFormula(cached!, label: "MFR reused \(run)") }
        cached = nil
        for run in 1...3 { try await measureFormula(FormulaRecognitionService(), label: "MFR recreated \(run)") }
        NSLog("[Recognition benchmark] After releasing services: %.1f MiB", footprintMB())
        let expiring = FormulaRecognitionService(modelIdleTimeout: 0.05)
        try await measureFormula(expiring, label: "MFR idle cache first")
        try await Task.sleep(for: .milliseconds(200))
        NSLog("[Recognition benchmark] After model idle eviction: %.1f MiB", footprintMB())
        try await measureFormula(expiring, label: "MFR idle cache reloaded")
    }
    
    /// Helper to synthesize a realistic screen capture bitmap matching macOS Retina 2x display scaling.
    /// - Parameters:
    ///   - lines: Text lines to draw.
    ///   - pointSize: The logical capture rectangle in points (e.g. 150x30 or 600x200).
    ///   - scaleFactor: Backing scale factor (default: 2.0 for Retina MacBook Pro).
    ///   - fontSize: Font size in points.
    private func createRetinaCaptureImage(
        lines: [String],
        pointSize: CGSize,
        scaleFactor: CGFloat = 2.0,
        fontSize: CGFloat = 13.0
    ) -> CGImage? {
        let pixelWidth = Int(pointSize.width * scaleFactor)
        let pixelHeight = Int(pointSize.height * scaleFactor)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Scale context so coordinates correspond directly to logical display points
        context.scaleBy(x: scaleFactor, y: scaleFactor)
        
        // Crisp white background
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(origin: .zero, size: pointSize))
        
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        ]
        
        let lineHeight = fontSize * 1.45
        var yPos = pointSize.height - (fontSize * 1.25)
        for line in lines {
            let attr = NSAttributedString(string: line, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attr)
            context.textPosition = CGPoint(x: 6.0, y: yPos)
            CTLineDraw(ctLine, context)
            yPos -= lineHeight
        }
        
        return context.makeImage()
    }
    
    /// Runs the full pipeline (Preprocessing -> Vision OCR -> String Reconstruction -> Clipboard)
    /// and returns the elapsed time and recognized text.
    private func runPipeline(on image: CGImage) async throws -> (Duration, String) {
        let clock = ContinuousClock()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var recognized = ""
        let duration = try await clock.measure {
            recognized = try await withCheckedThrowingContinuation { continuation in
                OCRService.performOCR(on: image) { result in
                    switch result {
                    case .success(let text):
                        continuation.resume(returning: text)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            ClipboardManager.copyToClipboard(text: recognized, pasteboard: pasteboard)
        }
        return (duration, recognized)
    }

    private func logBenchmark(_ text: String) {
        NSLog("%@", text)
    }

    @Test("Single-Line Short Sentence (~150x30 pt @ 2x Retina = 300x60 px)")
    func testSingleLineShortSentenceBenchmark() async throws {
        // Area: ~150x30 points, 4-6 words
        let sentence = ["Fast OCR in menu bar"]
        guard let image = createRetinaCaptureImage(
            lines: sentence,
            pointSize: CGSize(width: 150, height: 30),
            scaleFactor: 2.0,
            fontSize: 13.0
        ) else {
            Issue.record("Failed to synthesize single-line Retina image")
            return
        }
        
        // Warm-up run (loads neural engine weights into memory)
        _ = try await runPipeline(on: image)
        
        // Run separately from CI; seven samples make one slow Vision dispatch less dominant.
        var durationsMs: [Double] = []
        var lastRecognized = ""
        
        for _ in 1...7 {
            let (duration, text) = try await runPipeline(on: image)
            let ms = Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
            durationsMs.append(ms)
            lastRecognized = text
        }
        
        let medianMs = durationsMs.sorted()[durationsMs.count / 2]
        let minMs = durationsMs.min() ?? 0
        let maxMs = durationsMs.max() ?? 0
        
        let logOutput = String(
            format: """
            
            ========================================================================
            📊 Single-Line Sentence (~150x30 pt @ 2x = 300x60 px)
               • Text Content: "%@"
               • Median Latency: %.2f ms (Min: %.2f ms, Max: %.2f ms)
               • Extracted: "%@"
            ========================================================================
            
            """,
            sentence[0], medianMs, minMs, maxMs, lastRecognized.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        logBenchmark(logOutput)
        
        #expect(!lastRecognized.isEmpty)
    }

    @Test("Multi-Line Text Block (~600x200 pt @ 2x Retina = 1200x400 px)")
    func testMultiLineTextBlockBenchmark() async throws {
        // Area: ~600x200 points, multiline text paragraph
        let paragraph = [
            "CopyShot is a fast, native macOS menu bar utility for local OCR.",
            "Select any screen area to instantly extract text and copy to clipboard.",
            "Engineered for multi-monitor setups with Retina pixel scaling.",
            "All recognition runs locally on-device using Apple Vision framework.",
            "Optimized for minimal CPU and RAM usage with zero personal data access."
        ]
        
        guard let image = createRetinaCaptureImage(
            lines: paragraph,
            pointSize: CGSize(width: 600, height: 200),
            scaleFactor: 2.0,
            fontSize: 13.0
        ) else {
            Issue.record("Failed to synthesize multi-line Retina image")
            return
        }
        
        // Warm-up run
        _ = try await runPipeline(on: image)
        
        // Run separately from CI; seven samples make one slow Vision dispatch less dominant.
        var durationsMs: [Double] = []
        var lastRecognized = ""
        
        for _ in 1...7 {
            let (duration, text) = try await runPipeline(on: image)
            let ms = Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
            durationsMs.append(ms)
            lastRecognized = text
        }
        
        let medianMs = durationsMs.sorted()[durationsMs.count / 2]
        let minMs = durationsMs.min() ?? 0
        let maxMs = durationsMs.max() ?? 0
        
        let logOutput = String(
            format: """
            
            ========================================================================
            📊 Multi-Line Paragraph (~600x200 pt @ 2x = 1200x400 px)
               • Total Lines: %d, Characters: %d
               • Median Latency: %.2f ms (Min: %.2f ms, Max: %.2f ms)
            ========================================================================
            
            """,
            paragraph.count, lastRecognized.count, medianMs, minMs, maxMs
        )
        
        logBenchmark(logOutput)
        
        #expect(!lastRecognized.isEmpty)
    }
}
