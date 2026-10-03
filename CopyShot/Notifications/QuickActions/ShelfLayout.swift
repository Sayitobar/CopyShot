import SwiftUI
import AppKit

enum ShelfLayout {
    /// Bounded to the current catalog and stores layout metadata, never capture payloads or transforms.
    @MainActor
    final class Measurements {
        private struct Item: Equatable {
            let title: String
            let icon: ActionIcon
            let shortcut: Int?
            let hasSubmenu: Bool
        }
        private struct Entry {
            let items: [Item]
            let height: CGFloat
        }
        private enum Key: Hashable { case main, submenu(String) }
        private struct Environment: Equatable {
            let appearance: AppAppearance
            let effectiveAppearance: String?
            let numericShortcuts: Bool
            let debug: Bool
        }
        private let measure: ([QuickAction], Bool) -> CGFloat
        private var entries: [Key: Entry] = [:]
        private var environment: Environment?

        init(measure: @escaping ([QuickAction], Bool) -> CGFloat) { self.measure = measure }

        convenience init() {
            self.init { ShelfLayout.naturalHeight(actions: $0, submenu: $1) }
        }

        func invalidate() { entries.removeAll(); environment = nil }

        func prepare(actions: [QuickAction]) -> (main: CGFloat, submenu: CGFloat) {
            let keys: Set<Key> = Set([.main] + actions.filter(\.hasSubmenu).map { .submenu($0.id) })
            entries = entries.filter { keys.contains($0.key) }
            let main = height(actions: actions, key: .main, submenu: false)
            let submenu = actions.filter(\.hasSubmenu).map { submenuHeight(for: $0) }.max() ?? 0
            return (main, submenu)
        }

        func submenuHeight(for action: QuickAction) -> CGFloat {
            height(actions: action.subActions ?? [], key: .submenu(action.id), submenu: true)
        }

        private func height(actions: [QuickAction], key: Key, submenu: Bool) -> CGFloat {
            let settings = SettingsManager.shared
            let current = Environment(appearance: settings.presentationSettings.appearance,
                                      effectiveAppearance: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue,
                                      numericShortcuts: settings.presentationSettings.showNumericShortcuts,
                                      debug: settings.debugOverlay.isEnabled)
            if current != environment { entries.removeAll(); environment = current }
            let items = actions.map { Item(title: $0.title, icon: $0.icon, shortcut: $0.shortcutNumber, hasSubmenu: $0.hasSubmenu) }
            if let entry = entries[key], entry.items == items { return entry.height }
            let measured = measure(actions, submenu)
            entries[key] = Entry(items: items, height: measured)
            return measured
        }
    }

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
