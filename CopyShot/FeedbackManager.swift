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
    static func showNotification(title: String, subtitle: String? = nil, body: String, iconName: String, accentColor: Color, soundName: String? = nil) {
        shared.presenter.showNotification(
            title: title,
            subtitle: subtitle,
            body: body,
            iconName: iconName,
            accentColor: accentColor
        )
        
        // Play sound directly
        if let soundName = soundName {
            NSSound(named: soundName)?.play()
        }
    }
    
    // A simple, static function to play the screenshot sound.
    static func playSuccessSound() {
        NSSound(named: "Pop")?.play() // Changed to a less intrusive sound
    }
}
