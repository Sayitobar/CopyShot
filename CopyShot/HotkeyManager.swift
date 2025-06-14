//
//  HotkeyManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import Foundation
import Carbon // We need this for the low-level C-based Hotkey APIs

// A clean way to define a custom notification name.
// This helps us broadcast that the hotkey was pressed without tightly coupling our code.
extension Notification.Name {
    static let hotkeyWasPressed = Notification.Name("hotkeyWasPressed")
}

// This is the C-function that the OS will call when our hotkey is pressed.
// It acts as a bridge from the C world to our Swift class.
private func hotKeyHandler(callRef: EventHandlerCallRef?, eventRef: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    if let userData = userData {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotkey()
    }
    return noErr // Tell the OS we handled the event
}
// You must mark it with @convention(c) to make it passable as a C function pointer
private let hotKeyHandlerCallback: EventHandlerUPP = { (callRef, eventRef, userData) -> OSStatus in
    // Call into the Swift method using a bridge function
    return hotKeyHandler(callRef: callRef, eventRef: eventRef, userData: userData)
}

class HotkeyManager {
    // Singleton pattern: We only want one instance of this manager for the whole app.
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?

    private init() {} // Private initializer to enforce the singleton pattern.

    func register() {
        // 1. Define the Hotkey Signature
        // We need a unique ID for our hotkey. 'htk1' is just a unique 4-character code.
        let hotKeyID = EventHotKeyID(signature: "htk1".fourCharKode, id: 1)

        // 2. Define the Key Combination
        // kVK_ANSI_T is the key code for the 'T' key.
        // cmdKey and shiftKey are modifier flags.
        let keyCode = UInt32(kVK_ANSI_T)
        let modifiers = UInt32(cmdKey | shiftKey)

        // 3. Register the Hotkey with the System
        // This is the core C-function call.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        // We pass 'self' (our HotkeyManager instance) as user data.
        // This is how the C handler knows which Swift object to talk to.
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        // Check if registration was successful
        guard status == noErr else {
            print("Error: Unable to register hotkey")
            return
        }

        // 4. Tell the system which function to call when the hotkey is pressed.
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandlerCallback, 1, &eventType, selfPtr, nil)
        
        guard handlerStatus == noErr else {
            print("Error: Unable to install hotkey handler")
            return
        }
        
        print("Hotkey registered successfully: Command+Shift+T")
    }

    // This is the Swift method called by our C bridge function.
    func handleHotkey() {
        print("Hotkey pressed!")
        // Broadcast the notification to anyone in the app who is listening.
        NotificationCenter.default.post(name: .hotkeyWasPressed, object: nil)
        print("HotkeyManager: Notification .hotkeyWasPressed POSTED.")
    }
}

// Helper extension to make the fourCharKode conversion easier to read.
extension String {
    var fourCharKode: FourCharCode {
        return self.utf16.reduce(0, {$0 << 8 + FourCharCode($1)})
    }
}
