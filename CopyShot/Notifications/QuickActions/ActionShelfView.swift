//
//  ActionShelfView.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import SwiftUI

/// Stacked vertical list of Action Bars (Pills) positioned to the left of the notification HUD.
struct ActionShelfView: View {
    let actions: [QuickAction]
    let accentColor: Color
    let onActionSelected: (QuickAction) -> Void
    var onHoverChange: ((Bool) -> Void)? = nil
    
    // Geometry metrics matching NotificationPresenter
    static let paddingLeading: CGFloat = 12
    static let paddingTop: CGFloat = 10
    static let paddingBottom: CGFloat = 16
    static let hoverGapTrailing: CGFloat = 4
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(actions) { action in
                    ActionPillView(
                        action: action,
                        accentColor: accentColor,
                        onSelect: { onActionSelected(action) }
                    )
                }
            }
            
            // Continuous hit-test area extending 4pt to the right into the 8pt gap
            Color.black.opacity(0.001)
                .frame(width: Self.hoverGapTrailing)
                .debugZone("Shelf 4pt", type: .hover)
        }
        .contentShape(Rectangle())
        .debugZone("Shelf Hit Area", type: .hover)
        .onHover { isHovering in
            onHoverChange?(isHovering)
        }
        .padding(.leading, Self.paddingLeading)
        .padding(.trailing, 0)
        .padding(.top, Self.paddingTop)
        .padding(.bottom, Self.paddingBottom)
        .debugZone("Shelf Window", type: .windowBoundary)
    }
}
