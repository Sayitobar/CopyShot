//
//  DebugZoneModifier.swift
//  CopyShot
//
//  Created by Mac on 26.09.26.
//

import SwiftUI

/// Semantic types of debug zones for visual layout inspection.
///
/// Color Scheme:
/// - 🟦 **.hover (Blue):** Interactive hover hit-test boundaries (`.contentShape`, 4pt gap extensions)
/// - 🟩 **.windowBoundary (Green):** Outer window bounding boxes and breathing margins
/// - 🟧 **.interactive (Orange):** Clickable triggers & buttons (Close, Expand, Left Arrow, Action Pills, Tabs)
/// - 🟪 **.alignmentGuide (Purple):** Alignment guides and midpoint boundaries
enum DebugZoneType {
    case hover          // 🟦 Blue
    case windowBoundary // 🟩 Green
    case interactive    // 🟧 Orange
    case alignmentGuide // 🟪 Purple
    case custom(Color)
    
    var color: Color {
        switch self {
        case .hover: return .blue
        case .windowBoundary: return .green
        case .interactive: return .orange
        case .alignmentGuide: return .purple
        case .custom(let color): return color
        }
    }
}

/// View modifier rendering a semi-transparent dashed outline and badge for the layout zone when debug mode is enabled.
struct DebugZoneModifier: ViewModifier {
    @ObservedObject private var settings = SettingsManager.shared
    let label: String
    let type: DebugZoneType
    
    func body(content: Content) -> some View {
        if settings.showDebugOverlay {
            content.overlay(
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(type.color.opacity(0.85), style: StrokeStyle(lineWidth: 1.0, dash: [4, 2]))
                        .background(type.color.opacity(0.12))
                    
                    Text(label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(type.color.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .padding(2)
                }
                .allowsHitTesting(false)
            )
        } else {
            content
        }
    }
}

extension View {
    /// Overlays a color-coded inspection badge and dashed boundary when the developer debug layout overlay is active.
    ///
    /// Activated via **⇧⌥⌘D** (`Shift + Option + Cmd + D`) while the Settings window is open.
    func debugZone(_ label: String, type: DebugZoneType = .interactive) -> some View {
        self.modifier(DebugZoneModifier(label: label, type: type))
    }
}
