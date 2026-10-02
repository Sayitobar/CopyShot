import SwiftUI

struct ActionRowHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

enum ActionReorderLayout {
    static func targetIndex(order: [String], heights: [String: CGFloat], startIndex: Int, translation: CGFloat) -> Int {
        guard order.indices.contains(startIndex), order.allSatisfy({ (heights[$0] ?? 0) > 0 }) else { return startIndex }
        var origin: CGFloat = 0
        let centers = order.map { id -> CGFloat in
            let height = heights[id]!
            defer { origin += height }
            return origin + height / 2
        }
        let position = centers[startIndex] + translation
        return centers.indices.min { abs(centers[$0] - position) < abs(centers[$1] - position) } ?? startIndex
    }

    static func displacement(index: Int, start: Int, target: Int, draggedHeight: CGFloat) -> CGFloat {
        if start < target, index > start, index <= target { return -draggedHeight }
        if start > target, index >= target, index < start { return draggedHeight }
        return 0
    }
}

/// Collapsed natural height for the active Quick Actions mode; disclosures belong only to the live pane.
struct QuickActionsSettingsBaselineView: View {
    var mode: CaptureMode = .standardOCR
    
    var body: some View {
        QuickActionsSettingsView(baselineMode: mode)
            .fixedSize(horizontal: false, vertical: true)
    }
}
