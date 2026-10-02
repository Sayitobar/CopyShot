import SwiftUI
import AppKit

// MARK: - Modern Apple-Style Dropdown Picker Theme

struct ModernDropdownTheme {
    // Icon colors
    static let iconNormal = Color.secondary.opacity(0.8)
    static let iconHovered = Color.accentColor // Blue on hover
    
    // Label text
    static let textNormal = Color.primary
    
    // Dark mode colors
    static let bgDarkNormal = Color.white.opacity(0.07)
    static let bgDarkHovered = bgDarkNormal
    static let borderDarkNormal = Color.white.opacity(0.14)
    static let borderDarkHovered = Color.white.opacity(0.28)
    static let shadowDark = bgDarkNormal
    
    // Light mode colors
    static let bgLightNormal = Color.black.opacity(0.03)
    static let bgLightHovered = bgLightNormal
    static let borderLightNormal = Color.black.opacity(0.10)
    static let borderLightHovered = Color.black.opacity(0.22)
    static let shadowLight = bgLightNormal
    
    // Geometry & Layout Metrics
    static let cornerRadius: CGFloat = 6
    static let borderWidth: CGFloat = 0.75
    static let horizontalPadding: CGFloat = 9
    static let verticalPadding: CGFloat = 4.5
    static let contentSpacing: CGFloat = 6
    static let titleFontSize: CGFloat = 11.5
    static let iconFontSize: CGFloat = 8.5
    static let shadowRadius: CGFloat = 1.0
    static let shadowY: CGFloat = 0.5
    
    // Transitions & Durations
    static let hoverAnimationDuration: TimeInterval = 0.15
    static let hoverAnimation: Animation = .easeInOut(duration: hoverAnimationDuration)
    
    static func backgroundColor(isActive: Bool, isDark: Bool) -> Color {
        if isDark {
            return isActive ? bgDarkHovered : bgDarkNormal
        } else {
            return isActive ? bgLightHovered : bgLightNormal
        }
    }
    
    static func borderColor(isActive: Bool, isDark: Bool) -> Color {
        if isDark {
            return isActive ? borderDarkHovered : borderDarkNormal
        } else {
            return isActive ? borderLightHovered : borderLightNormal
        }
    }
    
    static func iconColor(isActive: Bool) -> Color {
        isActive ? iconHovered : iconNormal
    }
    
    static func shadowColor(isDark: Bool) -> Color {
        isDark ? shadowDark : shadowLight
    }
}

// MARK: - Dropdown Anchor View

private struct DropdownAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView)
        }
    }
}

// MARK: - Dropdown Menu Controller

private final class DropdownMenuController<T: Hashable>: NSObject, NSMenuDelegate {
    private var callback: ((T) -> Void)?
    private var dismissCallback: (() -> Void)?
    
    func show(
        items: [(id: T, title: String)],
        selection: T,
        anchorView: NSView?,
        onSelect: @escaping (T) -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.callback = onSelect
        self.dismissCallback = onDismiss
        
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        
        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(itemAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.id
            if item.id == selection {
                menuItem.state = .on
            }
            menu.addItem(menuItem)
        }
        
        let selectedItem = menu.items.first(where: { ($0.representedObject as? T) == selection })
        
        if let anchor = anchorView, anchor.window != nil {
            menu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: 0), in: anchor)
        } else if let window = NSApp.keyWindow ?? NSApp.windows.first, let contentView = window.contentView {
            let mouseLoc = window.mouseLocationOutsideOfEventStream
            menu.popUp(positioning: selectedItem, at: mouseLoc, in: contentView)
        }
    }
    
    @objc private func itemAction(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? T {
            callback?(id)
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        dismissCallback?()
    }
}

// MARK: - Modern Apple-Style Dropdown Picker

struct ModernDropdownPicker<T: Hashable>: View {
    let title: String
    let items: [(id: T, title: String)]
    @Binding var selection: T
    var minWidth: CGFloat = 140
    var width: CGFloat? = nil
    var overrideTitle: String? = nil
    var isEnabled: Bool = true
    var accessibilityIdentifier: String? = nil
    var onSelect: ((T) -> Void)? = nil
    
    @State private var isHovered = false
    @State private var isMenuOpen = false
    @State private var anchorView: NSView?
    @State private var menuController = DropdownMenuController<T>()
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    private var isActive: Bool {
        (isHovered || isMenuOpen) && isEnabled
    }
    
    private var currentTitle: String {
        overrideTitle ?? items.first(where: { $0.id == selection })?.title ?? title
    }
    
    var body: some View {
        Button {
            guard isEnabled else { return }
            isMenuOpen = true
            menuController.show(
                items: items,
                selection: selection,
                anchorView: anchorView,
                onSelect: { newSelection in
                    selection = newSelection
                    onSelect?(newSelection)
                },
                onDismiss: {
                    isMenuOpen = false
                }
            )
        } label: {
            HStack(spacing: ModernDropdownTheme.contentSpacing) {
                Text(currentTitle)
                    .font(.system(size: ModernDropdownTheme.titleFontSize, weight: .medium))
                    .foregroundStyle(isEnabled ? ModernDropdownTheme.textNormal : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer(minLength: 4)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: ModernDropdownTheme.iconFontSize, weight: .semibold))
                    .foregroundStyle(isEnabled ? ModernDropdownTheme.iconColor(isActive: isActive) : .secondary.opacity(0.5))
            }
            .padding(.horizontal, ModernDropdownTheme.horizontalPadding)
            .padding(.vertical, ModernDropdownTheme.verticalPadding)
            .frame(minWidth: width == nil ? minWidth : nil)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: ModernDropdownTheme.cornerRadius, style: .continuous)
                    .fill(ModernDropdownTheme.backgroundColor(isActive: isActive, isDark: isDark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ModernDropdownTheme.cornerRadius, style: .continuous)
                    .stroke(
                        ModernDropdownTheme.borderColor(isActive: isActive, isDark: isDark),
                        lineWidth: ModernDropdownTheme.borderWidth
                    )
            )
            .background(
                DropdownAnchorView { view in
                    self.anchorView = view
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: ModernDropdownTheme.cornerRadius, style: .continuous))
            .shadow(
                color: ModernDropdownTheme.shadowColor(isDark: isDark),
                radius: ModernDropdownTheme.shadowRadius,
                y: ModernDropdownTheme.shadowY
            )
            .animation(ModernDropdownTheme.hoverAnimation, value: isActive)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
        .onHover { hovering in
            if isEnabled {
                isHovered = hovering
            }
        }
    }
}
