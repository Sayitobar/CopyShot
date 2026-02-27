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
    let accentColor: Color
    
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isVisible: Bool
    
    var onHoverEnter: (() -> Void)? = nil
    var onHoverExit: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil
    
    // Testing parameter
    var enableIconShadow: Bool = false
    
    @State private var isHovering = false
    @State private var isExpanded = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(white: colorScheme == .dark ? 0.15 : 0.95), accentColor)
                .frame(width: 30)
                .shadow(color: enableIconShadow ? .black.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
            
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
                    Text(isExpanded ? (fullBodyText ?? bodyText) : bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(isExpanded ? nil : 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 344, alignment: .topLeading)
        .background(.regularMaterial) // Frosty glass material look
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) // Authentic Apple continuous corners
        // The signature Apple light boundary
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color(white: 1.0, opacity: 0.3) : Color(white: 0.0, opacity: 0.1), lineWidth: 0.5)
        )
        // Close Button (Top Leading)
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
            .offset(x: -6, y: -6)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        // Expand/Collapse Button (Bottom Trailing)
        .overlay(alignment: .bottomTrailing) {
            if let fullBody = fullBodyText, fullBody != bodyText, !bodyText.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 22, height: 22)
                        .background(Color(white: colorScheme == .dark ? 55.0/255.0 : 220.0/255.0))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.1), radius: 1)
                }
                .buttonStyle(.plain)
                .padding(10)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            }
        }
        .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .padding(.top, 14)
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isVisible)
        .onHover { isHoveringStatus in
            isHovering = isHoveringStatus
            if isHoveringStatus {
                onHoverEnter?()
            } else {
                onHoverExit?()
            }
        }
        .onAppear {
            isVisible = true
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ViewHeightKey.self, value: geometry.size.height)
        })
        .onPreferenceChange(ViewHeightKey.self) { newHeight in
            // When height expands or collapses, notify presenter to fix window size
            onHeightChange?(newHeight)
        }
    }
}

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
