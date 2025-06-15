//
//  ClipboardManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import AppKit

class ClipboardManager {
    
    // A simple, static function to copy text.
    static func copyToClipboard(text: String) {
        // Get a reference to the general pasteboard.
        let pasteboard = NSPasteboard.general
        
        // Clear any previous contents.
        pasteboard.clearContents()
        
        // Set the new content. We only care about string content.
        pasteboard.setString(text, forType: .string)
    }
}
