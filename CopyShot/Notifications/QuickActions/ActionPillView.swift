//
//  ActionPillView.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import SwiftUI
import AppKit

/// A single stacked action bar (pill shape) matching the notification HUD roundness and material aesthetic.
struct ActionPillView: View {
    let action: QuickAction
    let accentColor: Color
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Number badge for 1-9 direct keyboard access
                Text("\(action.shortcutNumber)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color(white: colorScheme == .dark ? 0.28 : 0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                
                // Action Icon / Logo
                iconView
                    .frame(width: 18, height: 18)
                
                // Action Title
                Text(action.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                // Subtle enter icon indicator on hover
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 0.6 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 216, height: 38, alignment: .leading)
            .background(
                // Base material matching notification box
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                // Hover highlight overlay
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.12 : 0.07) : 0))
            )
            .overlay(
                // Authentic Apple light boundary stroke
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color(white: 1.0, opacity: isHovered ? 0.35 : 0.2)
                            : Color(white: 0.0, opacity: isHovered ? 0.18 : 0.08),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.14 : 0.08), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .debugZone("Pill \(action.shortcutNumber)", type: .interactive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isHovered {
                // Tactile Mac feedback on hover
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            isHovered = hovering
        }
    }
    
    // MARK: - Action Icon / Logo Renderer
    
    private var iconView: some View {
        ActionIconView(
            icon: action.icon,
            size: 16,
            isHovered: isHovered,
            accentColor: accentColor
        )
    }
}

