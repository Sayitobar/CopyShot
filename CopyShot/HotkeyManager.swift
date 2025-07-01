//
//  HotkeyManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import Foundation
import Carbon

// Custom notification names for different hotkey actions
extension Notification.Name {
    static let captureHotkeyPressed = Notification.Name("captureHotkeyPressed")
    static let settingsHotkeyPressed = Notification.Name("settingsHotkeyPressed")
}

// C-function bridge for hotkey handling
private func hotKeyHandler(callRef: EventHandlerCallRef?, eventRef: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    if let userData = userData {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotkey(eventRef: eventRef)
    }
    return noErr
}

private let hotKeyHandlerCallback: EventHandlerUPP = { (callRef, eventRef, userData) -> OSStatus in
    return hotKeyHandler(callRef: callRef, eventRef: eventRef, userData: userData)
}

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    private var captureHotkeyRef: EventHotKeyRef?
    private var settingsHotkeyRef: EventHotKeyRef?
    private var isEventHandlerInstalled = false
    
    private init() {
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsChanged),
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil
        )
    }
    
    deinit {
        unregisterAllHotkeys()
        NotificationCenter.default.removeObserver(self)
    }
    
    func registerHotkeys() {
        let settings = SettingsManager.shared
        
        // Unregister existing hotkeys first
        unregisterAllHotkeys()
        
        // Install event handler if not already installed
        if !isEventHandlerInstalled {
            installEventHandler()
        }
        
        // Register capture hotkey
        registerHotkey(
            config: settings.captureHotkey,
            id: 1,
            hotkeyRef: &captureHotkeyRef
        )
        
        // Register settings hotkey
        registerHotkey(
            config: settings.settingsHotkey,
            id: 2,
            hotkeyRef: &settingsHotkeyRef
        )
    }
    
    private func registerHotkey(config: HotkeyConfig, id: UInt32, hotkeyRef: inout EventHotKeyRef?) {
        let hotKeyID = EventHotKeyID(signature: "htk1".fourCharKode, id: id)
        
        let status = RegisterEventHotKey(
            UInt32(config.keyCode),
            config.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status != noErr {
            print("Error registering hotkey \(config.displayString): \(status)")
        } else {
            print("Successfully registered hotkey: \(config.displayString)")
        }
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandlerCallback,
            1,
            &eventType,
            selfPtr,
            nil
        )
        
        if status == noErr {
            isEventHandlerInstalled = true
            print("Event handler installed successfully")
        } else {
            print("Error installing event handler: \(status)")
        }
    }
    
    func handleHotkey(eventRef: EventRef?) {
        guard let eventRef = eventRef else { return }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            OSType(kEventParamDirectObject),
            OSType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else {
            print("Error getting hotkey ID: \(status)")
            return
        }
        
        // Determine which hotkey was pressed based on ID
        switch hotKeyID.id {
        case 1: // Capture hotkey
            print("Capture hotkey pressed!")
            NotificationCenter.default.post(name: .captureHotkeyPressed, object: nil)
        case 2: // Settings hotkey
            print("Settings hotkey pressed!")
            NotificationCenter.default.post(name: .settingsHotkeyPressed, object: nil)
        default:
            print("Unknown hotkey pressed with ID: \(hotKeyID.id)")
        }
    }
    
    private func unregisterAllHotkeys() {
        if let captureRef = captureHotkeyRef {
            UnregisterEventHotKey(captureRef)
            captureHotkeyRef = nil
        }
        
        if let settingsRef = settingsHotkeyRef {
            UnregisterEventHotKey(settingsRef)
            settingsHotkeyRef = nil
        }
    }
    
    @objc private func hotkeySettingsChanged() {
        // Re-register hotkeys when settings change
        registerHotkeys()
    }
}

extension String {
    var fourCharKode: FourCharCode {
        return self.utf16.reduce(0, {$0 << 8 + FourCharCode($1)})
    }
}
