//
//  OverlayWindow.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import AppKit

// We create a custom NSWindow subclass.
class OverlayWindow: NSWindow {
    
    var onEscape: (() -> Void)?
    
    // We override this to allow the window to receive keyboard and mouse events.
    override var canBecomeKey: Bool {
        return true
    }
    
    // We add this override to allow the window to be the main window of the application.
    // For a single-window utility, this can be crucial.
    override var canBecomeMain: Bool {
        return true
    }
    
    // This function is called whenever a key is pressed while the window is key.
    override func keyDown(with event: NSEvent) {
        // The key code for the Escape key is 53.
        if event.keyCode == 53 {
            // If Escape is pressed, call our closure.
            onEscape?()
        } else {
            // For any other key, do nothing.
            super.keyDown(with: event)
        }
    }
}
