import AppKit
import Testing
@testable import CopyShot

@Suite("Optimization benchmarks", .serialized)
@MainActor
struct OptimizationBenchmarkTests {
    private func measure(_ label: String, iterations: Int = 30, operation: () throws -> Void) rethrows {
        try operation()
        var samples: [Double] = []
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            try operation()
            let elapsed = (ContinuousClock.now - start).components
            samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        samples.sort()
        NSLog("[Optimization benchmark] %@: median %.4f ms, p95 %.4f ms, n=%d",
              label, samples[samples.count / 2], samples[Int(Double(samples.count - 1) * 0.95)], iterations)
    }

    private func segments(rows: Int, columns: Int) -> [OCRService.TextSegment] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                .init(text: "Cell \(row)-\(column)", bounds: CGRect(
                    x: Double(column) / Double(columns), y: 1 - Double(row + 1) / Double(rows),
                    width: 0.8 / Double(columns), height: 0.6 / Double(rows)))
            }
        }
    }

    @Test("Dense reconstruction and action construction")
    func reconstructionAndActions() throws {
        let cells = segments(rows: 80, columns: 20)
        measure("OCR assembly 1600 segments") {
            #expect(!OCRService.assembleText(from: cells).isEmpty)
        }
        measure("Table clustering 1600 segments") {
            #expect(TableRecognitionService.cluster(cells).rows.count == 80)
        }
        let context = ActionContext(payload: .standardText("example.com/path"))
        let config = QuickActionsConfig()
        measure("OCR action catalog x100") {
            for _ in 0..<100 {
                #expect(!ActionRegistry.shared.actions(context: context, config: config).isEmpty)
            }
        }
        let actions = ActionRegistry.shared.actions(context: context, config: config)
        measure("Shelf measurements") {
            _ = ShelfLayout.naturalHeight(actions: actions, submenu: false)
            for children in actions.compactMap(\.subActions) {
                _ = ShelfLayout.naturalHeight(actions: children, submenu: true)
            }
        }
        let measurements = ShelfLayout.Measurements()
        measure("Shelf cached measurements") {
            _ = measurements.prepare(actions: actions)
        }
        measure("Submenu uncached height pair") {
            for action in actions where action.hasSubmenu {
                _ = ShelfLayout.naturalHeight(actions: action.subActions ?? [], submenu: true)
                _ = ShelfLayout.naturalHeight(actions: action.subActions ?? [], submenu: true)
            }
        }
        measure("Submenu cached height pair") {
            for action in actions where action.hasSubmenu {
                _ = measurements.submenuHeight(for: action)
                _ = measurements.submenuHeight(for: action)
            }
        }
    }

    @Test("Repeated notification presentation and formula preprocessing")
    func presentationAndPreprocessing() throws {
        let presenter = NotificationPresenter()
        defer { presenter.dismissNotification() }
        measure("Notification without actions") {
            presenter.showNotification(title: "No Text Found", body: "Nothing recognized.", accentColor: .blue)
            presenter.dismissNotification()
        }
        measure("Notification with OCR actions") {
            presenter.showNotification(title: "Text Copied", body: "example.com", accentColor: .green,
                                       supportsQuickActions: true)
            presenter.dismissNotification()
        }
        let context = try #require(CGContext(data: nil, width: 640, height: 140, bitsPerComponent: 8,
                                            bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 140))
        let image = try #require(context.makeImage())
        try measure("Formula preprocessing") {
            let tensor = try FormulaRecognitionService.preprocess(image)
            #expect(tensor.count == 3 * 384 * 384)
        }
        try measure("Formula direct encoder input") {
            let input = try FormulaRecognitionService.encoderInput(image)
            #expect(try input.tensorData().length == 3 * 384 * 384 * MemoryLayout<Float>.stride)
        }
    }
}
