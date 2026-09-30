import AppKit
import CoreText
import Testing
@testable import CopyShot

@Suite("MFR 1.5 integration")
struct FormulaRecognitionTests {
    @Test("MFR preprocessing preserves image orientation")
    func orientation() throws {
        let rgba: [UInt8] = [255, 0, 0, 255, 255, 0, 0, 255,
                             0, 0, 255, 255, 0, 0, 255, 255]
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8,
                                         bitsPerPixel: 32, bytesPerRow: 8,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false,
                                         intent: .defaultIntent))
        let tensor = try FormulaRecognitionService.preprocess(image)
        let blueChannel = 2 * 384 * 384
        let bottomLeft = blueChannel + 383 * 384
        #expect(tensor[0] > 0.9) // red at top left
        #expect(tensor[blueChannel] < -0.9) // no blue at top left
        #expect(tensor[bottomLeft] > 0.9) // blue at bottom left
    }

    @Test("The optional local model completes one real formula inference")
    func modelInference() async throws {
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyShot/MFR-1.5", isDirectory: true)
        let sandboxDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.sayitobar.CopyShot/Data/Library/Application Support/CopyShot/MFR-1.5", isDirectory: true)
        let resourcePath = ProcessInfo.processInfo.environment["COPYSHOT_MFR_MODEL_DIR"]
            ?? (FileManager.default.fileExists(atPath: defaultDirectory.appendingPathComponent("encoder_model.onnx").path)
                ? defaultDirectory.path : sandboxDirectory.path)
        guard FileManager.default.fileExists(atPath: resourcePath + "/encoder_model.onnx") else { return }
        setenv("COPYSHOT_MFR_MODEL_DIR", resourcePath, 1)
        let image = try #require(Self.makeFormulaImage())
        let service = FormulaRecognitionService()
        let start = CFAbsoluteTimeGetCurrent()
        let result = await withCheckedContinuation { continuation in
            service.recognize(image) { continuation.resume(returning: $0) }
        }
        let formulaResult = try result.get()
        #expect(!formulaResult.formula.isEmpty)
        let measurement = String(format: "MFR 1.5 first inference including model load: %.1f ms; output: %@",
                                 (CFAbsoluteTimeGetCurrent() - start) * 1_000, formulaResult.formula)
        print(measurement)
    }

    private static func makeFormulaImage() -> CGImage? {
        let width = 640
        let height = 140
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let text = NSAttributedString(string: "x² + y² = z²", attributes: [
            .font: NSFont.systemFont(ofSize: 64, weight: .regular),
            .foregroundColor: NSColor.black
        ])
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: 60, y: 42)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
