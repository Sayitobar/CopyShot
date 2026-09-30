import SwiftUI
import AppKit

enum ShelfLayout {
    static func viewportHeight(naturalHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(naturalHeight, max(0, availableHeight))
    }

    @MainActor
    static func naturalHeight(actions: [QuickAction], submenu: Bool) -> CGFloat {
        guard !actions.isEmpty else { return 0 }
        let view: AnyView
        if submenu {
            view = AnyView(ActionSubShelfView(subActions: actions, accentColor: .green, onActionSelected: { _ in }))
        } else {
            view = AnyView(ActionShelfView(actions: actions, accentColor: .green, onActionSelected: { _ in }))
        }
        let probe = NSHostingView(rootView: view.fixedSize(horizontal: false, vertical: true))
        return probe.fittingSize.height
    }
}

/// A shelf retains its natural column until screen bounds require an internal viewport.
struct ShelfScrollingColumn<Content: View>: View {
    var viewportHeight: CGFloat?
    let width: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let viewportHeight {
            ScrollView(.vertical, showsIndicators: true) { content() }
                .frame(width: width, height: viewportHeight)
        } else {
            content().frame(width: width)
        }
    }
}
