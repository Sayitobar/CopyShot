import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import CopyShot

@Suite("Barcode recognition")
struct BarcodeRecognitionTests {
    @Test("Vision decodes a generated QR capture")
    func detectsQR() async throws {
        let payload = "copyshot:qr-poc"
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(payload.utf8)
        let output = try #require(generator.outputImage)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let image = try #require(CIContext().createCGImage(scaled, from: scaled.extent))
        let result = await withCheckedContinuation { continuation in
            BarcodeRecognitionService.recognize(image) { continuation.resume(returning: $0) }
        }
        let codes = try result.get()
        #expect(codes.contains { $0.payload == payload })
    }
}
