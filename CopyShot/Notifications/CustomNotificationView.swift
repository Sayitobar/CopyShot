//
//  CustomNotificationView.swift
//  CopyShot
//
//  Created by Mac on 02.07.25.
//

import SwiftUI

struct CustomNotificationView: View {
    let title: String
    let subtitle: String?
    let bodyText: String
    let fullBodyText: String?
    let iconName: String
    var customIcon: ActionIcon? = nil
    let accentColor: Color
    
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isVisible: Bool
    
    var supportsQuickActions: Bool = false
    @Binding var isShelfOpen: Bool
    
    var onHoverEnter: (() -> Void)? = nil
    var onHoverExit: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onExpandShelf: (() -> Void)? = nil
    
    // Testing parameter
    var enableIconShadow: Bool = false
    
    @State private var isHoveringNotification = false
    @State private var isHoveringHandle = false
    @State private var isIndicatorVisible = false
    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var compactedHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // 1. Left Arrow Hover Indicator: Non-clickable hover trigger
                // Sized to the compacted notification HUD height.
                // Fixed in layout to eliminate any teleportation or layout shifts.
                // Fades in/out synchronously with cross and expand buttons (0.2s easeInOut).
                leftArrowIndicator
                    .opacity((supportsQuickActions && isIndicatorVisible && !isShelfOpen) ? 1 : 0)
                    .allowsHitTesting(supportsQuickActions && isIndicatorVisible && !isShelfOpen)
                    .animation(.easeInOut(duration: 0.2), value: isIndicatorVisible)
                    .animation(.easeInOut(duration: 0.2), value: isShelfOpen)
                
                // 2. Notification Box with 4pt leading hover extension (half of the 8pt gap)
                HStack(spacing: 0) {
                    // Extended hover zone: 4pt on the left (half of the 8pt gap)
                    Color.black.opacity(0.001)
                        .frame(width: 4, height: isExpanded ? (expandedHeight > 0 ? expandedHeight : 78) : (compactedHeight > 0 ? compactedHeight : 78))
                        .debugZone("HUD 4pt", type: .hover)
                    
                    // The Real Notification Box (hover state tracked strictly on this visible box)
                    notificationBox(expanded: isExpanded)
                        .background(
                            // Sizing Double: strictly for measuring collapsed height without affecting parent layout or hover bounds
                            notificationBox(expanded: false)
                                .opacity(0)
                                .allowsHitTesting(false)
                                .fixedSize(horizontal: false, vertical: true)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: CollapsedHeightKey.self, value: geometry.size.height)
                                    }
                                )
                                .frame(width: 344, height: 0, alignment: .topLeading)
                                .clipped()
                        )
                        .background(
                            // Sizing Double: strictly for measuring expanded height without affecting parent layout or hover bounds
                            notificationBox(expanded: true)
                                .opacity(0)
                                .allowsHitTesting(false)
                                .fixedSize(horizontal: false, vertical: true)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: ExpandedHeightKey.self, value: geometry.size.height)
                                    }
                                )
                                .frame(width: 344, height: 0, alignment: .topLeading)
                                .clipped()
                        )
                }
                .contentShape(Rectangle())
                .debugZone("HUD Hit Area", type: .hover)
                .onHover { hovering in
                    notificationHoverChanged(hovering)
                }
            }
            .padding(.trailing, 12)
            .padding(.leading, 12)
            .padding(.bottom, 28)
            .padding(.top, 14)
            .offset(y: isVisible ? 0 : -100)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isVisible)
            .onAppear {
                isVisible = true
            }
            
            // Push content to the top
            Spacer(minLength: 0)
        }
        // Anchored firmly to top-trailing. Window width is constant (400pt), completely eliminating any teleportation!
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onPreferenceChange(CollapsedHeightKey.self) { newHeight in
            guard newHeight > 0 else { return }
            compactedHeight = newHeight
            if !isExpanded {
                onHeightChange?(newHeight)
            }
        }
        .onPreferenceChange(ExpandedHeightKey.self) { newHeight in
            guard newHeight > 0 else { return }
            expandedHeight = newHeight
            if isExpanded {
                onHeightChange?(newHeight)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            let targetHeight = expanded ? expandedHeight : compactedHeight
            if targetHeight > 0 {
                onHeightChange?(targetHeight)
            }
        }
    }
    
    // MARK: - Left Arrow Hover Indicator (Non-clickable, pure hover trigger)
    
    @ViewBuilder
    private var leftArrowIndicator: some View {
        HStack(spacing: 0) {
            // Visual Pill (24pt wide)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color(white: 1.0, opacity: isHoveringHandle ? 0.35 : 0.2)
                                    : Color(white: 0.0, opacity: isHoveringHandle ? 0.18 : 0.08),
                                lineWidth: 0.5
                            )
                    )
                
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHoveringHandle ? accentColor : .secondary)
            }
            .frame(width: 24, height: compactedHeight > 0 ? compactedHeight : 78)
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: -1, y: 2)
            .debugZone("Arrow Pill", type: .interactive)
            
            // Extended hover zone: 4pt on the right (half of the 8pt gap)
            Color.black.opacity(0.001)
                .frame(width: 4, height: compactedHeight > 0 ? compactedHeight : 78)
                .debugZone("Arrow 4pt", type: .hover)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            handleHoverChanged(hovering)
        }
    }
    
    // MARK: - Notification Box
    
    @ViewBuilder
    private func notificationBox(expanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let customIcon = customIcon {
                ActionIconView(icon: customIcon, size: 24, isHovered: false, accentColor: accentColor)
                    .frame(width: 30, height: 30)
                    .shadow(color: enableIconShadow ? .black.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
            } else {
                Image(systemName: iconName.isEmpty ? "checkmark.circle.fill" : iconName)
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(white: colorScheme == .dark ? 0.15 : 0.95), accentColor)
                    .frame(width: 30)
                    .shadow(color: enableIconShadow ? .black.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if !bodyText.isEmpty {
                    Text(expanded ? (fullBodyText ?? bodyText) : bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(expanded ? nil : 4)
                }
            }
            Spacer(minLength: 0)
        }
        // NOTE: Custom floating HUD layout tuned for macOS 15.0+ Sequoia.
        // Geometry: 344pt width, 16pt continuous corner radius, regularMaterial.
        .padding(16)
        .frame(width: 344, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color(white: 1.0, opacity: 0.3) : Color(white: 0.0, opacity: 0.1), lineWidth: 0.5)
        )
        // Close Button (Top Leading) - only visible when hovering the notification box itself!
        .overlay(alignment: .topLeading) {
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 19, height: 19)
                    .background(Color(white: colorScheme == .dark ? 55.0/255.0 : 220.0/255.0))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .debugZone("Close", type: .interactive)
            .offset(x: -6, y: -6)
            .opacity(isHoveringNotification ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHoveringNotification)
        }
        // Expand/Collapse Button (Bottom Trailing) - only visible when hovering the notification box itself!
        .overlay(alignment: .bottomTrailing) {
            if let fullBody = fullBodyText, fullBody != bodyText, !bodyText.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 22, height: 22)
                        .background(Color(white: colorScheme == .dark ? 55.0/255.0 : 220.0/255.0))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.1), radius: 1)
                }
                .buttonStyle(.plain)
                .debugZone("Expand", type: .interactive)
                .padding(10)
                .opacity(isHoveringNotification ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHoveringNotification)
            }
        }
        .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 8)
    }
    
    // MARK: - Hover Handlers (Synchronized 0.2s easeInOut timing)
    
    private func notificationHoverChanged(_ hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isHoveringNotification = hovering
            if hovering {
                isIndicatorVisible = true
            } else if !isHoveringHandle {
                isIndicatorVisible = false
            }
        }
        
        if hovering {
            onHoverEnter?()
        } else {
            onHoverExit?()
        }
    }
    
    private func handleHoverChanged(_ hovering: Bool) {
        isHoveringHandle = hovering
        if hovering {
            onExpandShelf?()
        } else {
            if !isHoveringNotification {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isIndicatorVisible = false
                }
            }
        }
    }
}

// MARK: - Dynamic Preference Keys

struct CollapsedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ExpandedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
