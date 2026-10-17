import AppKit
import SwiftUI

@MainActor
final class CaptureModeSelection: ObservableObject {
    @Published var mode: CaptureMode
    var onModeSelected: ((CaptureMode) -> Void)?

    init(mode: CaptureMode = .standardOCR, onModeSelected: ((CaptureMode) -> Void)? = nil) {
        self.mode = mode
        self.onModeSelected = onModeSelected
    }

    func selectMode(_ newMode: CaptureMode) {
        mode = newMode
        onModeSelected?(newMode)
    }
}

@MainActor
final class CaptureModeInteraction: ObservableObject {
    let selection: CaptureModeSelection
    @Published private(set) var pressPoint: CGPoint?
    @Published private(set) var menuCenter: CGPoint?
    @Published private(set) var candidateIndex: Int?
    var selectedMode: CaptureMode { selection.mode }

    init(selection: CaptureModeSelection? = nil) {
        self.selection = selection ?? CaptureModeSelection()
    }

    func begin(at point: CGPoint, in canvas: CGSize? = nil) {
        pressPoint = point
        if let canvas {
            let radius = RadialModeSelection.menuDiameter / 2
            menuCenter = CGPoint(
                x: canvas.width >= 2 * radius ? min(max(point.x, radius), canvas.width - radius) : canvas.width / 2,
                y: canvas.height >= 2 * radius ? min(max(point.y, radius), canvas.height - radius) : canvas.height / 2
            )
        } else {
            menuCenter = point
        }
        candidateIndex = nil
    }

    func move(to point: CGPoint) {
        guard let pressPoint, let menuCenter else { return }
        let fromPress = CGPoint(x: point.x - pressPoint.x, y: point.y - pressPoint.y)
        let fromCenter = CGPoint(x: point.x - menuCenter.x, y: point.y - menuCenter.y)
        let next = hypot(fromPress.x, fromPress.y) <= RadialModeSelection.deadzoneRadius
            ? nil
            : RadialModeSelection.index(for: fromCenter, modeCount: CaptureModeDescriptor.available.count)
        if next != candidateIndex {
            if next != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            candidateIndex = next
        }
    }

    func end(at point: CGPoint) {
        guard pressPoint != nil else { return }
        move(to: point)
        if let candidateIndex {
            let selectedMode = CaptureModeDescriptor.available[candidateIndex].id
            selection.selectMode(selectedMode)
        }
        cancel()
    }

    func cancel() {
        pressPoint = nil
        menuCenter = nil
        candidateIndex = nil
    }
}

/// An N-sector rounded curved trapezoid shape whose adjacent facing edges
/// are strictly parallel lines separated by a constant slot width.
/// The inner edge curves concave along the central circular cutout,
/// the outer edge curves convex along the outer circle, with smooth outer corners
/// and crisp inner corners.
struct RoundedSectorShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let slotWidth: CGFloat
    let innerCornerRadius: CGFloat
    let outerCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        let rIn = max(1.0, innerRadius)
        let rOut = max(rIn + 4.0, outerRadius)
        let step = 2 * CGFloat.pi / CGFloat(count)
        let midA = -CGFloat.pi / 2 + CGFloat(index) * step
        let b1 = midA - step / 2
        let b2 = midA + step / 2
        let d = slotWidth / 2

        guard d < rIn, d < rOut else { return path }

        // Outer corner clamping for maximum smoothness
        let maxROutThick = (rOut - rIn) / 2.0
        let maxROutAngle = (rOut * sin(step / 2) - d) * 0.85
        let rO = max(1.0, min(outerCornerRadius, maxROutThick, maxROutAngle))

        // Inner corner clamping
        let maxRInThick = (rOut - rIn) / 2.4
        let maxRInAngle = (rIn * sin(step / 2) - d) * 0.75
        let rI = max(1.0, min(innerCornerRadius, maxRInThick, maxRInAngle))

        guard (d + rO) < (rOut - rO), (d + rI) < (rIn + rI) else { return path }

        let sinDeltaOut = (d + rO) / (rOut - rO)
        let sinDeltaIn = (d + rI) / (rIn + rI)
        guard sinDeltaOut < 0.999, sinDeltaIn < 0.999 else { return path }

        let deltaOut = asin(sinDeltaOut)
        let deltaIn = asin(sinDeltaIn)

        guard (b2 - deltaOut) > (b1 + deltaOut),
              (b2 - deltaIn) > (b1 + deltaIn) else { return path }

        // Unit vectors for ray 1 and normal pointing into sector
        let u1 = CGPoint(x: cos(b1), y: sin(b1))
        let n1 = CGPoint(x: -sin(b1), y: cos(b1))

        // Unit vectors for ray 2 and normal pointing into sector
        let u2 = CGPoint(x: cos(b2), y: sin(b2))
        let n2 = CGPoint(x: sin(b2), y: -cos(b2))

        // Fillet centers
        let cOut1 = CGPoint(
            x: center.x + (rOut - rO) * cos(b1 + deltaOut),
            y: center.y + (rOut - rO) * sin(b1 + deltaOut)
        )
        let cOut2 = CGPoint(
            x: center.x + (rOut - rO) * cos(b2 - deltaOut),
            y: center.y + (rOut - rO) * sin(b2 - deltaOut)
        )
        let cIn2 = CGPoint(
            x: center.x + (rIn + rI) * cos(b2 - deltaIn),
            y: center.y + (rIn + rI) * sin(b2 - deltaIn)
        )
        let cIn1 = CGPoint(
            x: center.x + (rIn + rI) * cos(b1 + deltaIn),
            y: center.y + (rIn + rI) * sin(b1 + deltaIn)
        )

        // Contact distances along rays
        let tOut = sqrt(max(0, (rOut - rO) * (rOut - rO) - (d + rO) * (d + rO)))
        let tIn = sqrt(max(0, (rIn + rI) * (rIn + rI) - (d + rI) * (d + rI)))

        guard tOut > tIn else { return path }

        // Points along parallel Side 1:
        let pSide1In = CGPoint(x: center.x + d * n1.x + tIn * u1.x, y: center.y + d * n1.y + tIn * u1.y)
        let pSide1Out = CGPoint(x: center.x + d * n1.x + tOut * u1.x, y: center.y + d * n1.y + tOut * u1.y)

        // Point along parallel Side 2:
        let pSide2In = CGPoint(x: center.x + d * n2.x + tIn * u2.x, y: center.y + d * n2.y + tIn * u2.y)

        // 1. Start on Side 1 after inner fillet 4
        path.move(to: pSide1In)

        // 2. Straight line up Side 1 (strictly parallel to adjacent sector!)
        path.addLine(to: pSide1Out)

        // 3. Fillet 1 (outer start): turns from Side 1 into outer circle with smooth rO
        path.addArc(center: cOut1, radius: rO,
                    startAngle: .radians(b1 - .pi / 2),
                    endAngle: .radians(b1 + deltaOut),
                    clockwise: false)

        // 4. Outer arc (convex): curves along outer circle
        path.addArc(center: center, radius: rOut,
                    startAngle: .radians(b1 + deltaOut),
                    endAngle: .radians(b2 - deltaOut),
                    clockwise: false)

        // 5. Fillet 2 (outer end): turns from outer circle into Side 2 with smooth rO
        path.addArc(center: cOut2, radius: rO,
                    startAngle: .radians(b2 - deltaOut),
                    endAngle: .radians(b2 + .pi / 2),
                    clockwise: false)

        // 6. Straight line down Side 2 (strictly parallel to adjacent sector!)
        path.addLine(to: pSide2In)

        // 7. Fillet 3 (inner end): turns from Side 2 into inner circle with rI
        path.addArc(center: cIn2, radius: rI,
                    startAngle: .radians(b2 + .pi / 2),
                    endAngle: .radians(b2 - deltaIn + .pi),
                    clockwise: false)

        // 8. Inner arc (concave): curves along central circular cutout
        path.addArc(center: center, radius: rIn,
                    startAngle: .radians(b2 - deltaIn),
                    endAngle: .radians(b1 + deltaIn),
                    clockwise: true)

        // 9. Fillet 4 (inner start): turns from inner circle into Side 1 with rI
        path.addArc(center: cIn1, radius: rI,
                    startAngle: .radians(b1 + deltaIn + .pi),
                    endAngle: .radians(b1 - .pi / 2),
                    clockwise: false)

        path.closeSubpath()
        return path
    }
}

/// A hollow circular ring / annulus shape that backs the radial sectors
struct RadialBackingRing: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: .zero, endAngle: .radians(2 * .pi), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: .radians(2 * .pi), endAngle: .zero, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct RadialMenuSegmentView: View {
    let descriptor: CaptureModeDescriptor
    let index: Int
    let count: Int
    let isSelected: Bool
    let diameter: CGFloat
    let innerRadius: CGFloat

    var body: some View {
        let step = 2 * CGFloat.pi / CGFloat(count)
        let centerAngle = -CGFloat.pi / 2 + CGFloat(index) * step
        let inR: CGFloat = innerRadius
        let outR: CGFloat = diameter / 2 - 4
        let slotW: CGFloat = count > 6 ? 4.0 : (count >= 5 ? 4.5 : 5.0)
        let rIn: CGFloat = 9.0
        let rOut: CGFloat = count > 6 ? 16.0 : (count >= 5 ? 10.0 : 12.0)

        let shape = RoundedSectorShape(
            index: index,
            count: count,
            innerRadius: inR,
            outerRadius: outR,
            slotWidth: slotW,
            innerCornerRadius: rIn,
            outerCornerRadius: rOut
        )
        let iconRadius = (inR + outR) / 2

        ZStack {
            shape
                .fill(.regularMaterial)
            shape
                .fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.85),
                                    Color.accentColor.opacity(0.60)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(Color.primary.opacity(0.06))
                )
                .animation(.snappy(duration: 0.2, extraBounce: 0.04), value: isSelected)

            // Static uniform boundary: completely eliminates any outline animation or stroke width jump
            shape
                .stroke(Color.primary.opacity(0.14), lineWidth: 1.0)
                .transaction { $0.animation = nil }

            VStack(spacing: 2) {
                Image(systemName: descriptor.symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(descriptor.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .animation(.snappy(duration: 0.2, extraBounce: 0.04), value: isSelected)
            .frame(width: max(36, iconRadius * 2 * .pi / CGFloat(count) - 14), height: 36)
            .position(x: diameter / 2 + iconRadius * cos(centerAngle),
                      y: diameter / 2 + iconRadius * sin(centerAngle))
        }
    }
}

struct RadialCaptureMenu: View {
    let descriptors: [CaptureModeDescriptor]
    let candidateIndex: Int?

    private let diameter = RadialModeSelection.menuDiameter
    private let innerRadius: CGFloat = 40
    private let ringPadding: CGFloat = 4

    var body: some View {
        let backingRing = RadialBackingRing(
            innerRadius: max(1.0, innerRadius - ringPadding),
            outerRadius: diameter / 2
        )

        ZStack {
            // Very slightly larger background circle (hollow inside)
            backingRing
                .fill(.ultraThinMaterial)
            backingRing
                .fill(Color.primary.opacity(0.04))
            backingRing
                .stroke(Color.primary.opacity(0.12), lineWidth: 1.0)

            ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                RadialMenuSegmentView(
                    descriptor: descriptor,
                    index: index,
                    count: descriptors.count,
                    isSelected: candidateIndex == index,
                    diameter: diameter,
                    innerRadius: innerRadius
                )
                .zIndex(candidateIndex == index ? 1 : 0)
            }
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
        .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}
