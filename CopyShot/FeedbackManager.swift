//
//  FeedbackManager.swift
//  CopyShot
//
//  Created by Mac on 01.07.25.
//

import Foundation
import UserNotifications
import AppKit // For NSSound

class FeedbackManager {
    
    // A simple, static function to show the "Text Copied" notification.
    static func showNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        
        // Check if we have permission before trying to send.
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            
            // We can add a sound to the notification itself.
            // .default is a subtle, standard sound.
            content.sound = UNNotificationSound.default
            
            // Create the request. A nil trigger sends it immediately.
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            
            // Add the request to the notification center.
            center.add(request)
        }
    }
    
    // A simple, static function to play the screenshot sound.
    // We will make this optional in the future.
    static func playSuccessSound() {
        NSSound(named: "Tink")?.play()
    }
}
