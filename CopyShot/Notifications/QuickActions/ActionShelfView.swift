//
//  ActionShelfView.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import SwiftUI

/// Stacked vertical list of Action Bars (Pills) positioned to the left of the notification HUD.
/// Anchored to a fixed-width window (232pt) that never mutates its frame during hover interactions.
struct ActionShelfView: View {
    let actions: [QuickAction]
    let accentColor: Color
    var viewportHeight: CGFloat? = nil
    var activeSubmenuId: String? = nil
    var isSubShelfHovered: Bool = false
    let onActionSelected: (QuickAction) -> Void
    var onMainPillHover: ((QuickAction, Bool) -> Void)? = nil
    var onHoverChange: ((Bool) -> Void)? = nil
    
    @State private var hoveredActionId: String? = nil
    
    // Geometry metrics matching NotificationPresenter
    static let paddingLeading: CGFloat = 12
    static let paddingTop: CGFloat = 10
    static let paddingBottom: CGFloat = 16
    static let hoverGapTrailing: CGFloat = 4
    static let pillWidth: CGFloat = 216
    static let columnGap: CGFloat = 8
    
    // Theme & Animation Configuration
    struct Theme {
        static let dimmedOpacity: Double = 0.38
        static let activeOpacity: Double = 1.0
        static let dimAnimationDuration: TimeInterval = 0.2
        static let dimAnimation: Animation = .easeInOut(duration: dimAnimationDuration)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Main Shelf column (stationary, locked to trailing edge)
            ShelfScrollingColumn(viewportHeight: viewportHeight, width: Self.pillWidth) {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(actions) { action in
                        let isParent = activeSubmenuId == action.id
                        let isDimmed = isSubShelfHovered && !isParent
                        let isHovered = hoveredActionId == action.id
                    
                        ActionPillView(
                            action: action,
                            accentColor: accentColor,
                            isSubmenuActive: isParent,
                            isHovered: isHovered,
                            onSelect: { onActionSelected(action) },
                            onHover: { hovering in
                                if hovering {
                                    hoveredActionId = action.id
                                } else if hoveredActionId == action.id {
                                    hoveredActionId = nil
                                }
                                onMainPillHover?(action, hovering)
                            }
                        )
                        .opacity(isDimmed ? Theme.dimmedOpacity : Theme.activeOpacity)
                        .animation(Theme.dimAnimation, value: isDimmed)
                    }
                }
            }
            .frame(width: Self.pillWidth)
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .debugZone("Main Shelf Column", type: .interactive)
            
            // Continuous hit-test area extending 4pt to the right into the 8pt gap
            Color.black.opacity(0.001)
                .frame(width: Self.hoverGapTrailing)
                .contentShape(Rectangle())
                .debugZone("Shelf 4pt", type: .hover)
        }
        .contentShape(Rectangle())
        .debugZone("Shelf Hit Area", type: .hover)
        .onHover { isHovering in
            if !isHovering {
                hoveredActionId = nil
            }
            onHoverChange?(isHovering)
        }
        .padding(.leading, Self.paddingLeading)
        .padding(.trailing, 0)
        .padding(.top, Self.paddingTop)
        .padding(.bottom, Self.paddingBottom)
        .debugZone("Shelf Window", type: .windowBoundary)
    }
}

/// Flyout sub-shelf column hosted in an independent floating child window positioned to the left of the main shelf.
struct ActionSubShelfView: View {
    let subActions: [QuickAction]
    let accentColor: Color
    var viewportHeight: CGFloat? = nil
    var isMainShelfHovered: Bool = false
    let onActionSelected: (QuickAction) -> Void
    var onHoverChange: ((Bool) -> Void)? = nil
    
    @State private var hoveredSubActionId: String? = nil
    
    static let paddingLeading: CGFloat = 12
    static let paddingTop: CGFloat = 10
    static let paddingBottom: CGFloat = 16
    static let pillWidth: CGFloat = 216
    static let bridgeTrailing: CGFloat = 8
    
    var body: some View {
        HStack(spacing: 0) {
            ShelfScrollingColumn(viewportHeight: viewportHeight, width: Self.pillWidth) {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(subActions) { subAction in
                        let isHovered = hoveredSubActionId == subAction.id
                        ActionPillView(
                            action: subAction,
                            accentColor: accentColor,
                            isHovered: isHovered,
                            onSelect: { onActionSelected(subAction) },
                            onHover: { hovering in
                                if hovering {
                                    hoveredSubActionId = subAction.id
                                } else if hoveredSubActionId == subAction.id {
                                    hoveredSubActionId = nil
                                }
                            }
                        )
                        .opacity(isMainShelfHovered ? ActionShelfView.Theme.dimmedOpacity : ActionShelfView.Theme.activeOpacity)
                        .animation(ActionShelfView.Theme.dimAnimation, value: isMainShelfHovered)
                    }
                }
            }
            .frame(width: Self.pillWidth)
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .debugZone("Sub-Shelf Column", type: .interactive)
            
            // Continuous 8pt hit-test bridge extending to the right to meet the main shelf pill
            Color.black.opacity(0.001)
                .frame(width: Self.bridgeTrailing)
                .contentShape(Rectangle())
                .debugZone("Sub-Shelf Bridge 8pt", type: .hover)
        }
        .contentShape(Rectangle())
        .debugZone("Sub-Shelf Hit Area", type: .hover)
        .onHover { isHovering in
            if !isHovering {
                hoveredSubActionId = nil
            }
            onHoverChange?(isHovering)
        }
        .padding(.leading, Self.paddingLeading)
        .padding(.trailing, 0)
        .padding(.top, Self.paddingTop)
        .padding(.bottom, Self.paddingBottom)
        .debugZone("Sub-Shelf Window", type: .windowBoundary)
    }
}
