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
    let iconName: String
    let accentColor: Color
    
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isVisible: Bool
    
    var onHoverEnter: (() -> Void)? = nil
    var onHoverExit: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 30)
            
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
                    Text(bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
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
        .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .padding(.top, 14)
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isVisible)
        .onHover { isHovering in
            if isHovering {
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
    }
}

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
