import AppKit

/// Immutable evidence from one actual OCR request. Ownership is limited to its HUD and inspector.
final class OCRInspection: Equatable {
    struct Region: Identifiable {
        let id: Int
        let text: String
        let bounds: CGRect
        let confidence: Float
    }

    struct Timings {
        let preprocessing: Double
        let recognition: Double
        let assembly: Double
    }

    let id = UUID()
    let original: CGImage
    let input: CGImage
    let preprocessing: OCRPreprocessor.Status
    let configuration: OCRService.Configuration
    let regions: [Region]
    let assembledText: String
    let timings: Timings
    let errorDescription: String?

    init(original: CGImage, input: CGImage, preprocessing: OCRPreprocessor.Status,
         configuration: OCRService.Configuration, regions: [Region], assembledText: String,
         timings: Timings, errorDescription: String? = nil) {
        self.original = original
        self.input = input
        self.preprocessing = preprocessing
        self.configuration = configuration
        self.regions = regions
        self.assembledText = assembledText
        self.timings = timings
        self.errorDescription = errorDescription
    }

    static func == (lhs: OCRInspection, rhs: OCRInspection) -> Bool { lhs === rhs }
}

enum InspectionGeometry {
    /// A centered image in a scrollable canvas that is at least the viewport's size.
    static func imageRect(imageSize: CGSize, viewport: CGSize, zoom: CGFloat,
                          actualSize: Bool = false, displayScale: CGFloat = 1) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = actualSize ? zoom / max(1, displayScale) :
            min(viewport.width / imageSize.width, viewport.height / imageSize.height) * zoom
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: max(0, (viewport.width - size.width) / 2),
                      y: max(0, (viewport.height - size.height) / 2), width: size.width, height: size.height)
    }

    static func regionRect(_ bounds: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + bounds.minX * imageRect.width,
               y: imageRect.minY + (1 - bounds.maxY) * imageRect.height,
               width: bounds.width * imageRect.width, height: bounds.height * imageRect.height)
    }

    static func revealOrigin(regionRect: CGRect, canvasSize: CGSize, viewport: CGSize) -> CGPoint {
        CGPoint(x: min(max(0, regionRect.midX - viewport.width / 2), max(0, canvasSize.width - viewport.width)),
                y: min(max(0, regionRect.midY - viewport.height / 2), max(0, canvasSize.height - viewport.height)))
    }
}
