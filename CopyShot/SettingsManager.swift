//
//  SettingsManager.swift
//  CopyShot
//
//  Created by Mac on 21.06.25.
//

import Foundation
import Vision
import Carbon
import AppKit // Import for NSEvent
import SwiftUI
import ServiceManagement

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// Define keys for our settings to avoid typos.
enum SettingsKeys {
    static let recognitionLevel = "recognitionLevel"
    static let usesLanguageCorrection = "usesLanguageCorrection"
    static let recognitionLanguages = "recognitionLanguages"
    static let captureHotkey = "captureHotkey"
    static let textPreviewLimit = "textPreviewLimit"
    static let appAppearance = "appAppearance"
    static let playNotificationSound = "playNotificationSound"
}

// Using an enum for the recognition level makes our code safer and clearer.
enum RecognitionLevel: Int, CaseIterable, Identifiable {
    case accurate = 1
    case fast = 0
    
    var id: Int { self.rawValue }
    
    var description: String {
        switch self {
            case .accurate: return "Accurate"
            case .fast: return "Fast"
        }
    }
}

// Hotkey configuration structure
struct HotkeyConfig: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt32
    let displayString: String
    
    init(keyCode: UInt16, modifierFlags: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayString = displayString
    }
    
    static let defaultCapture = HotkeyConfig(
        keyCode: UInt16(kVK_ANSI_C),
        modifierFlags: UInt32(cmdKey | shiftKey),
        displayString: "⌘⇧C"
    )
}

class SettingsManager: ObservableObject {
    // Singleton pattern to access settings from anywhere.
    static let shared = SettingsManager()
    
    // @Published properties will automatically update any SwiftUI views that use them.
    @Published var recognitionLevel: RecognitionLevel {
        didSet {
            UserDefaults.standard.set(recognitionLevel.rawValue, forKey: SettingsKeys.recognitionLevel)
        }
    }
    
    @Published var usesLanguageCorrection: Bool {
        didSet {
            UserDefaults.standard.set(usesLanguageCorrection, forKey: SettingsKeys.usesLanguageCorrection)
        }
    }
    
    @Published var recognitionLanguages: [String] {
        didSet {
            UserDefaults.standard.set(recognitionLanguages, forKey: SettingsKeys.recognitionLanguages)
        }
    }
    
    @Published var captureHotkey: HotkeyConfig {
        didSet {
            saveHotkey(captureHotkey, forKey: SettingsKeys.captureHotkey)
        }
    }
    
    @Published var textPreviewLimit: Int {
        didSet {
            UserDefaults.standard.set(textPreviewLimit, forKey: SettingsKeys.textPreviewLimit)
        }
    }
    
    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: SettingsKeys.appAppearance)
        }
    }
    
    @Published var playNotificationSound: Bool {
        didSet {
            UserDefaults.standard.set(playNotificationSound, forKey: SettingsKeys.playNotificationSound)
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            if #available(macOS 13.0, *) {
                do {
                    if launchAtLogin {
                        if SMAppService.mainApp.status == .notRegistered {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    debugPrint("Failed to update launch at login status: \(error)")
                }
            }
        }
    }
    
    private init() {
        // MARK: - Initial Settings Check & Assignment
        // Here we assign the default values for the first time the app is launched.
        // If a setting does not exist in UserDefaults (is nil), we provide the fallback default.
        
        // Recognition Level (Default: Accurate)
        if UserDefaults.standard.object(forKey: SettingsKeys.recognitionLevel) == nil {
            self.recognitionLevel = .accurate
        } else {
            let savedLevel = UserDefaults.standard.integer(forKey: SettingsKeys.recognitionLevel)
            self.recognitionLevel = RecognitionLevel(rawValue: savedLevel) ?? .accurate
        }
        
        // Language Correction (Default: True)
        if UserDefaults.standard.object(forKey: SettingsKeys.usesLanguageCorrection) == nil {
            self.usesLanguageCorrection = true
        } else {
            self.usesLanguageCorrection = UserDefaults.standard.bool(forKey: SettingsKeys.usesLanguageCorrection)
        }
        
        // Languages (Default: English)
        self.recognitionLanguages = UserDefaults.standard.stringArray(forKey: SettingsKeys.recognitionLanguages) ?? ["en-US"]
        
        // Hotkeys (Default: ⌘⇧C)
        self.captureHotkey = HotkeyConfig.defaultCapture
        if let savedCaptureHotkey = Self.loadHotkey(forKey: SettingsKeys.captureHotkey) {
            self.captureHotkey = savedCaptureHotkey
        }
        
        // Text Preview Limit (Default: 50)
        let limit = UserDefaults.standard.integer(forKey: SettingsKeys.textPreviewLimit)
        self.textPreviewLimit = limit == 0 ? 50 : limit
        
        // App Appearance (Default: System)
        if UserDefaults.standard.object(forKey: SettingsKeys.appAppearance) == nil {
            self.appearance = .system
        } else {
            let savedAppearance = UserDefaults.standard.string(forKey: SettingsKeys.appAppearance) ?? AppAppearance.system.rawValue
            self.appearance = AppAppearance(rawValue: savedAppearance) ?? .system
        }
        
        // Notification Sound
        if UserDefaults.standard.object(forKey: SettingsKeys.playNotificationSound) == nil {
            self.playNotificationSound = true
        } else {
            self.playNotificationSound = UserDefaults.standard.bool(forKey: SettingsKeys.playNotificationSound)
        }
        
        // Launch at Login (Default: False)
        // SMAppService defaults to .notRegistered on first launch, ensuring it stays disabled natively.
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = false
        }
    }
    
    // Helper property to get available languages from Vision
    var supportedLanguages: [String] {
        let request = VNRecognizeTextRequest()
        do {
            return try request.supportedRecognitionLanguages()
        } catch {
            return ["en-US"] // Fallback
        }
    }
    
    // MARK: - Hotkey Management
    
    private func saveHotkey(_ hotkey: HotkeyConfig, forKey key: String) {
        if let encoded = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private static func loadHotkey(forKey key: String) -> HotkeyConfig? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return nil
        }
        return hotkey
    }
    
    // Reset hotkeys to defaults
    func resetHotkeysToDefaults() {
        captureHotkey = HotkeyConfig.defaultCapture
    }
    
    // Check if hotkey is already in use
    func isHotkeyInUse(_ hotkey: HotkeyConfig) -> Bool {
        return hotkey == captureHotkey
    }
    
    // Convert NSEvent modifier flags to Carbon flags
    static func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }
        return carbonFlags
    }
    
    // Generate display string for modifiers and key
    static func displayString(for keyCode: UInt16, modifierFlags: UInt32) -> String {
        var result = ""
        
        if modifierFlags & UInt32(controlKey) != 0 {
            result += "⌃"
        }
        if modifierFlags & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if modifierFlags & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if modifierFlags & UInt32(cmdKey) != 0 {
            result += "⌘"
        }
        
        // Convert key code to character
        let keyString = keyCodeToString(keyCode)
        result += keyString
        
        return result
    }
    
    // Convert key code to readable string
    private static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case UInt16(kVK_ANSI_A): return "A"
        case UInt16(kVK_ANSI_B): return "B"
        case UInt16(kVK_ANSI_C): return "C"
        case UInt16(kVK_ANSI_D): return "D"
        case UInt16(kVK_ANSI_E): return "E"
        case UInt16(kVK_ANSI_F): return "F"
        case UInt16(kVK_ANSI_G): return "G"
        case UInt16(kVK_ANSI_H): return "H"
        case UInt16(kVK_ANSI_I): return "I"
        case UInt16(kVK_ANSI_J): return "J"
        case UInt16(kVK_ANSI_K): return "K"
        case UInt16(kVK_ANSI_L): return "L"
        case UInt16(kVK_ANSI_M): return "M"
        case UInt16(kVK_ANSI_N): return "N"
        case UInt16(kVK_ANSI_O): return "O"
        case UInt16(kVK_ANSI_P): return "P"
        case UInt16(kVK_ANSI_Q): return "Q"
        case UInt16(kVK_ANSI_R): return "R"
        case UInt16(kVK_ANSI_S): return "S"
        case UInt16(kVK_ANSI_T): return "T"
        case UInt16(kVK_ANSI_U): return "U"
        case UInt16(kVK_ANSI_V): return "V"
        case UInt16(kVK_ANSI_W): return "W"
        case UInt16(kVK_ANSI_X): return "X"
        case UInt16(kVK_ANSI_Y): return "Y"
        case UInt16(kVK_ANSI_Z): return "Z"
        case UInt16(kVK_ANSI_0): return "0"
        case UInt16(kVK_ANSI_1): return "1"
        case UInt16(kVK_ANSI_2): return "2"
        case UInt16(kVK_ANSI_3): return "3"
        case UInt16(kVK_ANSI_4): return "4"
        case UInt16(kVK_ANSI_5): return "5"
        case UInt16(kVK_ANSI_6): return "6"
        case UInt16(kVK_ANSI_7): return "7"
        case UInt16(kVK_ANSI_8): return "8"
        case UInt16(kVK_ANSI_9): return "9"
        case UInt16(kVK_ANSI_Comma): return ","
        case UInt16(kVK_ANSI_Period): return "."
        case UInt16(kVK_ANSI_Slash): return "/"
        case UInt16(kVK_ANSI_Semicolon): return ";"
        case UInt16(kVK_ANSI_Quote): return "'"
        case UInt16(kVK_ANSI_LeftBracket): return "["
        case UInt16(kVK_ANSI_RightBracket): return "]"
        case UInt16(kVK_ANSI_Backslash): return "\\"
        case UInt16(kVK_ANSI_Grave): return "`"
        case UInt16(kVK_ANSI_Minus): return "-"
        case UInt16(kVK_ANSI_Equal): return "="
        case UInt16(kVK_Space): return "Space"
        case UInt16(kVK_Return): return "Return"
        case UInt16(kVK_Tab): return "Tab"
        case UInt16(kVK_Delete): return "Delete"
        case UInt16(kVK_Escape): return "Escape"
        case UInt16(kVK_F1): return "F1"
        case UInt16(kVK_F2): return "F2"
        case UInt16(kVK_F3): return "F3"
        case UInt16(kVK_F4): return "F4"
        case UInt16(kVK_F5): return "F5"
        case UInt16(kVK_F6): return "F6"
        case UInt16(kVK_F7): return "F7"
        case UInt16(kVK_F8): return "F8"
        case UInt16(kVK_F9): return "F9"
        case UInt16(kVK_F10): return "F10"
        case UInt16(kVK_F11): return "F11"
        case UInt16(kVK_F12): return "F12"
        case UInt16(kVK_UpArrow): return "↑"
        case UInt16(kVK_DownArrow): return "↓"
        case UInt16(kVK_LeftArrow): return "←"
        case UInt16(kVK_RightArrow): return "→"
        default: return "Unknown"
        }
    }
}
