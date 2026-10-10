import CoreImage
import CoreGraphics

/// The existing OCR recipe, shared with lazy inspection previews.
enum OCRPreprocessor {
    enum Status: Equatable {
        case applied
        case originalFallback(String)

        var explanation: String {
            switch self {
            case .applied: "Monochrome conversion and contrast ×1.5 applied."
            case .originalFallback(let reason): "Original image used. \(reason)"
            }
        }
    }

    private static let context = CIContext(options: nil)

    static func process(_ original: CGImage) -> (image: CGImage, status: Status) {
        guard let mono = monochrome(CIImage(cgImage: original)),
              let contrast = CIFilter(name: "CIColorControls") else {
            return (original, .originalFallback("Preprocessing filters unavailable."))
        }
        contrast.setValue(mono, forKey: kCIInputImageKey)
        contrast.setValue(1.5, forKey: kCIInputContrastKey)
        guard let output = contrast.outputImage,
              let image = context.createCGImage(output, from: output.extent) else {
            return (original, .originalFallback("Preprocessing could not render an image."))
        }
        return (image, .applied)
    }

    static func monochromePreview(_ original: CGImage) -> CGImage? {
        guard let output = monochrome(CIImage(cgImage: original)) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    private static func monochrome(_ image: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage
    }
}
