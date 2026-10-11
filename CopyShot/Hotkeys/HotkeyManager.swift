//
//  HotkeyManager.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import Foundation
import Carbon
import Combine

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
    
    @Published var registrationError: String?
    private var settingsObserver: AnyCancellable?
    private var eventHandlerRef: EventHandlerRef?
    private var isEventHandlerInstalled = false
    private let settings: SettingsManager
    private let registration: HotkeyRegistration

    static func registerSystemHotkey(_ config: HotkeyConfig) throws -> EventHotKeyRef {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(config.keyCode), config.modifierFlags,
                                        EventHotKeyID(signature: "htk1".fourCharKode, id: 1),
                                        GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else { throw HotkeyRegistrationError.unavailable(status) }
        return reference
    }
    
    init(settings: SettingsManager = .shared, registration: HotkeyRegistration? = nil) {
        self.settings = settings
        self.registration = registration ?? HotkeyRegistration(register: Self.registerSystemHotkey, unregister: { UnregisterEventHotKey($0) })
        settingsObserver = settings.$captureHotkey.dropFirst().sink { [weak self] config in
            // Published emits before assignment; use the emitted candidate, including resets.
            self?.register(config)
        }
    }
    
    deinit {
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
    
    func registerHotkeys() {
        register(settings.captureHotkey)
    }

    /// Call before persisting a recorded candidate so registration failure is reversible.
    func setCaptureHotkey(_ config: HotkeyConfig) throws {
        do {
            if !isEventHandlerInstalled { try installEventHandler() }
            try registration.replace(with: config)
        } catch {
            logRegistrationFailure(error)
            throw error
        }
        registrationError = nil
        settings.captureHotkey = config
    }

    private func register(_ config: HotkeyConfig) {
        do {
            if !isEventHandlerInstalled { try installEventHandler() }
            try registration.replace(with: config)
            registrationError = nil
        } catch {
            logRegistrationFailure(error)
            registrationError = error.localizedDescription
            // A reset may have written the candidate already. Restore the registered value.
            if let active = registration.activeConfig, config != active {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.settings.captureHotkey == config else { return }
                    self.settings.captureHotkey = active
                    self.registrationError = message
                }
            }
        }
    }

    private func logRegistrationFailure(_ error: Error) {
        if case HotkeyRegistrationError.unavailable(let status) = error {
            DiagnosticLog.shared.record(.hotkeyRegistrationFailed, code: Int(status))
        } else { DiagnosticLog.shared.record(.hotkeyRegistrationFailed, error: error) }
    }
    
    private func installEventHandler() throws {
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
            &eventHandlerRef
        )
        
        if status == noErr {
            isEventHandlerInstalled = true
            print("Event handler installed successfully")
        } else {
            throw HotkeyRegistrationError.unavailable(status)
        }
    }
    
    fileprivate func handleHotkey(eventRef: EventRef?) {
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
            DiagnosticLog.shared.record(.hotkeyEventFailed, code: Int(status))
            print("Error getting hotkey ID: \(status)")
            return
        }
        
        // Determine which hotkey was pressed based on ID
        switch hotKeyID.id {
        case 1: // Capture hotkey
            print("Capture hotkey pressed!")
            NotificationCenter.default.post(name: .captureHotkeyPressed, object: nil)
        default:
            print("Unknown hotkey pressed with ID: \(hotKeyID.id)")
        }
    }
    
}

extension String {
    var fourCharKode: FourCharCode {
        return self.utf16.reduce(0, {$0 << 8 + FourCharCode($1)})
    }
}
