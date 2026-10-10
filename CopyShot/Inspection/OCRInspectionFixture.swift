#if DEBUG
import AppKit
import CoreText

/// Synthetic inspector launch data for desktop UI tests. Never captures the screen or writes the clipboard.
enum OCRInspectionFixture {
    static func make(empty: Bool = false) -> OCRInspection {
        let width = 1000
        let height = 340
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let lines = empty ? [] : ["Understand every capture.", "See the image. Follow the processing.", "Your text stays on your Mac."]
        var regions: [OCRInspection.Region] = []
        for (index, text) in lines.enumerated() {
            let pointSize: CGFloat = index == 0 ? 40 : 30
            let string = NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, pointSize, nil),
                .foregroundColor: index == 0 ? CGColor(red: 0.08, green: 0.3, blue: 0.65, alpha: 1) : NSColor.black.cgColor
            ])
            let line = CTLineCreateWithAttributedString(string)
            let origin = CGPoint(x: 48, y: 240 - CGFloat(index) * 75)
            context.textPosition = origin
            CTLineDraw(line, context)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).offsetBy(dx: origin.x, dy: origin.y)
            regions.append(.init(id: index + 1, text: text,
                                 bounds: CGRect(x: bounds.minX / CGFloat(width), y: bounds.minY / CGFloat(height),
                                                width: bounds.width / CGFloat(width), height: bounds.height / CGFloat(height)),
                                 confidence: 0.98 - Float(index) * 0.07))
        }
        let original = context.makeImage()!
        let processed = OCRPreprocessor.process(original)
        return OCRInspection(original: original, input: processed.image, preprocessing: processed.status,
                             configuration: OCRService.Configuration(), regions: regions,
                             assembledText: lines.joined(separator: "\n"),
                             timings: .init(preprocessing: 1.7, recognition: 37.2, assembly: 0.2))
    }
}
#endif
