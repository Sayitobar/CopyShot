//
//  ActionPillView.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import SwiftUI
import AppKit

// MARK: - Action Pill Theme

struct ActionPillTheme {
    static let pillWidth: CGFloat = 216
    static let pillHeight: CGFloat = 38
    static let cornerRadius: CGFloat = 14
    static let borderWidth: CGFloat = 0.5
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    
    static let hoverScale: CGFloat = 1.015
    static let normalScale: CGFloat = 1.0
    
    static let hoverAnimationDuration: TimeInterval = 0.1
    static let activeAnimationDuration: TimeInterval = 0.15
    static let hoverAnimation: Animation = .easeInOut(duration: hoverAnimationDuration)
    static let activeAnimation: Animation = .easeInOut(duration: activeAnimationDuration)
    
    static func highlightOpacity(isHovered: Bool, isSubmenuActive: Bool, isDark: Bool) -> Double {
        if isHovered {
            return isDark ? 0.12 : 0.07
        } else if isSubmenuActive {
            return isDark ? 0.06 : 0.04
        } else {
            return 0.0
        }
    }
    
    static func borderStrokeColor(isHovered: Bool, isSubmenuActive: Bool, isDark: Bool) -> Color {
        if isDark {
            let opacity = isHovered ? 0.35 : (isSubmenuActive ? 0.25 : 0.20)
            return Color(white: 1.0, opacity: opacity)
        } else {
            let opacity = isHovered ? 0.18 : (isSubmenuActive ? 0.12 : 0.08)
            return Color(white: 0.0, opacity: opacity)
        }
    }
    
    static func shadowOpacity(isHovered: Bool, isSubmenuActive: Bool) -> Double {
        isHovered ? 0.14 : (isSubmenuActive ? 0.10 : 0.08)
    }
    
    static func shadowRadius(isHovered: Bool) -> CGFloat {
        isHovered ? 8 : 4
    }
    
    static func shadowY(isHovered: Bool) -> CGFloat {
        isHovered ? 4 : 2
    }
    
    static func chevronOpacity(isActive: Bool) -> Double {
        isActive ? 0.9 : 0.45
    }
    
    static func returnOpacity(isHovered: Bool) -> Double {
        isHovered ? 0.6 : 0.0
    }
}

/// A single stacked action bar (pill shape) matching the notification HUD roundness and material aesthetic.
struct ActionPillView: View {
    let action: QuickAction
    let accentColor: Color
    var isSubmenuActive: Bool = false
    var isHovered: Bool = false
    let onSelect: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isActive: Bool {
        isHovered || isSubmenuActive
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Number badge for 1-9 direct keyboard access
                if SettingsManager.shared.quickActionsConfig.showNumericShortcuts {
                    Text("\(action.shortcutNumber)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color(white: colorScheme == .dark ? 0.28 : 0.86))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                // Action Icon / Logo
                iconView
                    .frame(width: 18, height: 18)
                
                // Action Title (supports up to 22+ chars without truncation)
                Text(action.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                
                Spacer(minLength: 2)
                
                // Trailing indicator: Left chevron for flyouts, return arrow for direct actions
                if action.hasSubmenu {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .opacity(ActionPillTheme.chevronOpacity(isActive: isActive))
                } else {
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .opacity(ActionPillTheme.returnOpacity(isHovered: isHovered))
                }
            }
            .padding(.horizontal, ActionPillTheme.horizontalPadding)
            .padding(.vertical, ActionPillTheme.verticalPadding)
            .frame(width: ActionPillTheme.pillWidth, height: ActionPillTheme.pillHeight, alignment: .leading)
            .background(
                // Base material matching notification box
                RoundedRectangle(cornerRadius: ActionPillTheme.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                // Hover & active highlight overlay
                RoundedRectangle(cornerRadius: ActionPillTheme.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(ActionPillTheme.highlightOpacity(isHovered: isHovered, isSubmenuActive: isSubmenuActive, isDark: colorScheme == .dark)))
            )
            .overlay(
                // Authentic Apple light boundary stroke
                RoundedRectangle(cornerRadius: ActionPillTheme.cornerRadius, style: .continuous)
                    .stroke(
                        ActionPillTheme.borderStrokeColor(isHovered: isHovered, isSubmenuActive: isSubmenuActive, isDark: colorScheme == .dark),
                        lineWidth: ActionPillTheme.borderWidth
                    )
            )
            .shadow(
                color: Color.black.opacity(ActionPillTheme.shadowOpacity(isHovered: isHovered, isSubmenuActive: isSubmenuActive)),
                radius: ActionPillTheme.shadowRadius(isHovered: isHovered),
                x: 0,
                y: ActionPillTheme.shadowY(isHovered: isHovered)
            )
            .scaleEffect(isHovered ? ActionPillTheme.hoverScale : ActionPillTheme.normalScale)
            .animation(ActionPillTheme.hoverAnimation, value: isHovered)
            .animation(ActionPillTheme.activeAnimation, value: isSubmenuActive)
            .contentShape(RoundedRectangle(cornerRadius: ActionPillTheme.cornerRadius, style: .continuous))
            .debugZone("Pill \(action.shortcutNumber)", type: .interactive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isHovered && SettingsManager.shared.quickActionsConfig.playHapticsOnHover {
                // Tactile Mac feedback on hover
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            onHover?(hovering)
        }
    }
    
    // MARK: - Action Icon / Logo Renderer
    
    private var iconView: some View {
        ActionIconView(
            icon: action.icon,
            size: 16,
            isHovered: isActive,
            accentColor: accentColor
        )
    }
}

