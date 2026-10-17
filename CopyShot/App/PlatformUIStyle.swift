import SwiftUI

/// Explicit drawing budget for a shadow's blur tail, offset, and optional hover scale.
struct FloatingShadowMetrics {
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    func outsets(size: CGSize = .zero, scale: CGFloat = 1) -> EdgeInsets {
        // Reserve three blur radii so the Gaussian tail fades before the canvas edge.
        let tail = 3 * radius
        let horizontalScale = max(0, size.width * (scale - 1) / 2)
        let verticalScale = max(0, size.height * (scale - 1) / 2)
        return EdgeInsets(top: ceil(max(0, tail - y + verticalScale)),
                          leading: ceil(max(0, tail - x + horizontalScale)),
                          bottom: ceil(max(0, tail + y + verticalScale)),
                          trailing: ceil(max(0, tail + x + horizontalScale)))
    }
}

enum NotificationHUDLayout {
    static let bodyWidth: CGFloat = 344
    static let handleWidth: CGFloat = 24
    static let hoverBridge: CGFloat = 4
    static let handleShadow = FloatingShadowMetrics(radius: 4, x: -1, y: 2)
    // Glass controls share the strongest configured floating-shadow envelope.
    static var leadingInset: CGFloat {
        max(12, max(handleShadow.outsets().leading, ActionPillTheme.shadowDrawingInsets.leading))
    }
    static let trailingInset: CGFloat = 12
    static let topInset: CGFloat = 14
    static let bottomInset: CGFloat = 28
    static let closeButtonDiameter: CGFloat = 19
    static var closeButtonInset: CGFloat {
        guard PlatformUIStyle.usesLiquidGlass else { return -6 }
        // Circular diagonal reference for the continuous HUD corner.
        return PlatformUIStyle.notificationCornerRadius * (1 - 1 / sqrt(2)) - closeButtonDiameter / 2
    }
    static var closeButtonOverhang: CGFloat { max(0, -closeButtonInset) }
    static var bodyLeading: CGFloat { leadingInset + handleWidth + 2 * hoverBridge }
    static var shelfBridgeEnd: CGFloat { bodyLeading - hoverBridge }
    static var width: CGFloat { bodyLeading + bodyWidth + trailingInset }
}

/// Appearance choices, not layout compensation. Geometry continues to come from measured views.
enum PlatformUIStyle {
    static var usesLiquidGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
    static var controlCornerRadius: CGFloat { usesLiquidGlass ? 10 : 6 }
    static var groupCornerRadius: CGFloat { usesLiquidGlass ? 14 : 8 }
    static var notificationCornerRadius: CGFloat { usesLiquidGlass ? 24 : 16 }
    static var lightModeControlGray: Double { (usesLiquidGlass ? 234.0 : 226.0) / 255 }
}

/// Glass captures its foreground as well as its shape. Apply it to the actual content,
/// not an empty background shape, so GlassEffectContainer composites labels correctly.
struct FloatingSurface: ViewModifier {
    let cornerRadius: CGFloat
    var capsule = false
    var interactive = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if capsule {
                content.glassEffect(.regular.interactive(interactive), in: Capsule())
            } else {
                content.glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.regularMaterial)
            }
        }
    }
}

/// Small controls sit on the HUD's glass: use an adaptive material rather than
/// another Liquid Glass layer or a fixed gray disc.
struct HUDControlBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26, *) {
            Circle().fill(.regularMaterial)
        } else {
            Circle().fill(Color(white: colorScheme == .dark ? 55.0 / 255 : 220.0 / 255))
        }
    }
}

struct ShelfMaterialContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            // Pills remain distinct; adjacent effects must not merge during hover.
            GlassEffectContainer(spacing: 0, content: content)
        } else { content() }
    }
}
