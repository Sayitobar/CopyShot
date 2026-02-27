//
//  FeedbackManager.swift
//  CopyShot
//
//  Created by Mac on 01.07.25.
//

import Foundation
import UserNotifications
import AppKit // For NSSound
import SwiftUI // For Color

class FeedbackManager {
    
    static let shared = FeedbackManager()
    let presenter = NotificationPresenter()
    
    private init() {}
    
    // A simple, static function to show the "Text Copied" notification.
    static func showNotification(title: String, subtitle: String? = nil, body: String, fullBody: String? = nil, iconName: String, accentColor: Color, soundName: String? = nil) {
        shared.presenter.showNotification(
            title: title,
            subtitle: subtitle,
            body: body,
            fullBody: fullBody,
            iconName: iconName,
            accentColor: accentColor
        )
        
        // Play sound directly
        if let soundName = soundName, SettingsManager.shared.playNotificationSound {
            NSSound(named: soundName)?.play()
        }
    }
    
    // A simple, static function to play the screenshot sound.
    static func playSuccessSound() {
        if SettingsManager.shared.playNotificationSound {
            NSSound(named: "Pop")?.play()
        }
    }
}

// MARK: - Adaptive Colors for Light/Dark Mode Matching

extension Color {
    static var adaptiveGreen: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.name == .darkAqua ? .systemGreen : NSColor(red: 0.05, green: 0.5, blue: 0.15, alpha: 1.0)
        }))
    }
    static var adaptiveGray: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.name == .darkAqua ? .systemGray : NSColor(white: 0.35, alpha: 1.0)
        }))
    }
    static var adaptiveRed: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.name == .darkAqua ? .systemRed : NSColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1.0)
        }))
    }
    static var adaptiveOrange: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.name == .darkAqua ? .systemOrange : NSColor(red: 0.85, green: 0.4, blue: 0.0, alpha: 1.0)
        }))
    }
    static var adaptiveBlue: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.name == .darkAqua ? .systemBlue : NSColor(red: 0.1, green: 0.35, blue: 0.85, alpha: 1.0)
        }))
    }
}
