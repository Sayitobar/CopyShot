import XCTest
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
}
