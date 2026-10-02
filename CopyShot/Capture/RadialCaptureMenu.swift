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
        pressPoint = nil
        menuCenter = nil
        candidateIndex = nil
    }
}

private struct RingSegment: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let step = 2 * CGFloat.pi / CGFloat(count)
        let centerAngle = -CGFloat.pi / 2 + CGFloat(index) * step
        let gap = min(0.11, step * 0.16)
        let start = centerAngle - step / 2 + gap / 2
        let end = centerAngle + step / 2 - gap / 2
        let radius = min(rect.width, rect.height) * 0.34
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for sample in 0...32 {
            let angle = start + (end - start) * CGFloat(sample) / 32
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct RadialCaptureMenu: View {
    let descriptors: [CaptureModeDescriptor]
    let candidateIndex: Int?

    private let diameter = RadialModeSelection.menuDiameter

    var body: some View {
        ZStack {
            ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                let segment = RingSegment(index: index, count: descriptors.count)
                segment
                    .stroke(.regularMaterial, style: StrokeStyle(lineWidth: 47, lineCap: .round))
                segment
                    .stroke(candidateIndex == index ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                            style: StrokeStyle(lineWidth: 47, lineCap: .round))
                segment
                    .strokeBorderIfSelected(candidateIndex == index)

                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(descriptors.count)
                let radius = diameter * 0.34
                VStack(spacing: 2) {
                    Image(systemName: descriptor.symbol)
                        .font(.system(size: 16, weight: .semibold))
                    Text(descriptor.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.primary)
                .frame(width: max(34, radius * 2 * .pi / CGFloat(descriptors.count) - 9), height: 36)
                .position(x: diameter / 2 + radius * cos(angle),
                          y: diameter / 2 + radius * sin(angle))
            }
            Circle()
                .fill(.regularMaterial)
                .frame(width: 49, height: 49)
                .overlay(Image(systemName: "plus.viewfinder").font(.system(size: 16)).foregroundStyle(.secondary))
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .allowsHitTesting(false)
    }
}

private extension Shape {
    @ViewBuilder
    func strokeBorderIfSelected(_ selected: Bool) -> some View {
        if selected {
            stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
