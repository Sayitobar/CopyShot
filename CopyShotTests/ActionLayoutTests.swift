import XCTest
import SwiftUI
@testable import CopyShot

final class ActionLayoutTests: XCTestCase {
    func testReorderTargetsUseMeasuredRowsRatherThanFixedStride() {
        let heights: [String: CGFloat] = ["a": 40, "b": 70, "c": 30]
        XCTAssertEqual(ActionReorderLayout.targetIndex(order: ["a", "b", "c"], heights: heights, startIndex: 0, translation: 60), 1)
        XCTAssertEqual(ActionReorderLayout.targetIndex(order: ["a", "b", "c"], heights: heights, startIndex: 2, translation: -110), 0)
        XCTAssertEqual(ActionReorderLayout.displacement(index: 1, start: 0, target: 2, draggedHeight: 40), -40)
        XCTAssertEqual(ActionReorderLayout.displacement(index: 1, start: 2, target: 0, draggedHeight: 30), 30)
    }

    func testShelfViewportClampsToVisibleHeight() {
        XCTAssertEqual(ShelfLayout.viewportHeight(naturalHeight: 620, availableHeight: 300), 300)
        XCTAssertEqual(ShelfLayout.viewportHeight(naturalHeight: 100, availableHeight: 300), 100)
        XCTAssertEqual(ShelfLayout.viewportHeight(naturalHeight: 100, availableHeight: -2), 0)
    }

    @MainActor
    func testShelfCanvasContainsTheHoverShadow() {
        let action = QuickAction(id: "fixture", title: "Fixture", icon: .system("star"), shortcutNumber: nil)
        let host = NSHostingView(rootView: ActionShelfView(actions: [action], accentColor: .green,
                                                         onActionSelected: { _ in })
            .fixedSize(horizontal: true, vertical: true))
        // The 8pt hover blur needs a 24pt tail, plus 1.62pt of horizontal scaling.
        // A 216pt pill therefore needs 26pt on either side, plus its 4pt hover bridge.
        XCTAssertGreaterThanOrEqual(host.fittingSize.width, 272)
    }

    func testShadowMarginsDoNotBecomeShelfTargets() {
        let main = ShelfLayout.interactiveRect(windowSize: CGSize(width: 272, height: 200), bridgeWidth: 4)
        XCTAssertTrue(main.contains(CGPoint(x: 100, y: 100)))
        XCTAssertTrue(main.contains(CGPoint(x: 245, y: 100)), "The existing four-point bridge remains usable.")
        for point in [CGPoint(x: 1, y: 100), CGPoint(x: 271, y: 100),
                      CGPoint(x: 100, y: 1), CGPoint(x: 100, y: 199)] {
            XCTAssertFalse(main.contains(point))
        }
        let submenu = ShelfLayout.interactiveRect(windowSize: CGSize(width: 276, height: 200),
                                                  bridgeWidth: 8, activeHeight: 140)
        XCTAssertTrue(submenu.contains(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(submenu.contains(CGPoint(x: 100, y: 50)), "The unused lower part of a submenu canvas is transparent.")
    }
}
