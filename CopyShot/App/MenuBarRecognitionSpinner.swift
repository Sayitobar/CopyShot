import AppKit
import SwiftUI

/// MenuBarExtra renders labels as status-item images, so animate the image frames themselves.
struct MenuBarRecognitionSpinner: View {
    @State private var phase = 0
    private let ticks = Timer.publish(every: 1.0 / 12.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Image(nsImage: Self.frames[phase])
            .accessibilityLabel("Recognizing capture")
            .onReceive(ticks) { _ in phase = (phase + 1) % Self.frames.count }
    }

    private static let frames: [NSImage] = (0..<12).map { phase in
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            for spoke in 0..<12 {
                let angle = Double(spoke) * .pi / 6
                let age = (spoke - phase + 12) % 12
                NSColor.black.withAlphaComponent(0.15 + 0.85 * Double(age) / 11).setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1.8
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: 11 + sin(angle) * 4, y: 11 + cos(angle) * 4))
                path.line(to: NSPoint(x: 11 + sin(angle) * 8, y: 11 + cos(angle) * 8))
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
