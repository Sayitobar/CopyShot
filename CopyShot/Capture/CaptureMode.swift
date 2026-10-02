import CoreGraphics
import Foundation

enum CaptureMode: String, Hashable, Codable {
    case standardOCR
    case qrBarcode
    case latex
    case table
}

enum CaptureModeBehavior: String, CaseIterable, Identifiable, Codable {
    case always = "always"
    case rememberLast = "rememberLast"
    case returnToDefaultAfterTimeout = "returnToDefaultAfterTimeout"
    
    var id: String { rawValue }
    
    var displayTitle: String {
        switch self {
        case .always: return "Always Default"
        case .rememberLast: return "Stick to Last Selected"
        case .returnToDefaultAfterTimeout: return "Reset After Inactivity"
        }
    }
}

struct CaptureModeDescriptor: Identifiable, Hashable {
    let id: CaptureMode
    let title: String
    let symbol: String

    // Order and count for both the menu and capture routing come from this list.
    static let available: [Self] = [
        .init(id: .standardOCR, title: "OCR", symbol: "text.viewfinder"),
        .init(id: .qrBarcode, title: "QR", symbol: "qrcode.viewfinder"),
        .init(id: .latex, title: "LaTeX", symbol: "function"),
        .init(id: .table, title: "Table", symbol: "tablecells")
    ]

    static func descriptor(for mode: CaptureMode) -> Self? {
        available.first { $0.id == mode }
    }
}

enum RadialModeSelection {
    static let deadzoneRadius: CGFloat = 28
    static let menuDiameter: CGFloat = 184

    /// Coordinates are relative to the press point, with positive y downward.
    /// The first descriptor is at twelve o'clock and following ones run clockwise.
    static func index(for offset: CGPoint, modeCount: Int) -> Int? {
        guard modeCount > 0, hypot(offset.x, offset.y) > deadzoneRadius else { return nil }
        let clockwiseFromTop = atan2(offset.x, -offset.y)
        let normalized = (clockwiseFromTop + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return Int((normalized / (2 * .pi / Double(modeCount)) + 0.5).rounded(.down)) % modeCount
    }
}
