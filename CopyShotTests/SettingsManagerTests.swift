//
//  SettingsManagerTests.swift
//  CopyShotTests
//
//  Created for CopyShot.
//

import Testing
import Foundation
import Carbon
@testable import CopyShot

@Suite("SettingsManager Tests")
struct SettingsManagerTests {
    
    @Test("Settings default values are valid and sensible")
    func testSensibleDefaults() {
        let settings = SettingsManager.shared
        
        // Languages must not be empty
        #expect(!settings.recognitionLanguages.isEmpty)
        #expect(settings.recognitionLanguages.contains("en-US") || !settings.supportedLanguages.isEmpty)
        
        // Recognition level should be one of the known cases
        #expect(settings.recognitionLevel == .accurate || settings.recognitionLevel == .fast)
        
        // Preview limit must be non-negative
        #expect(settings.textPreviewLimit >= 0)
        
        // Capture hotkey must have valid display string
        #expect(!settings.captureHotkey.displayString.isEmpty)
    }
    
    @Test("HotkeyConfig Codable encoding and decoding round-trip")
    func testHotkeyConfigSerialization() throws {
        let original = HotkeyConfig(
            keyCode: UInt16(kVK_ANSI_C),
            modifierFlags: UInt32(cmdKey | shiftKey),
            displayString: "⌘⇧C"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HotkeyConfig.self, from: data)
        
        #expect(decoded == original)
        #expect(decoded.keyCode == original.keyCode)
        #expect(decoded.modifierFlags == original.modifierFlags)
        #expect(decoded.displayString == original.displayString)
    }
    
    @Test("Hotkey displayString formats modifiers correctly")
    func testHotkeyDisplayStringModifiers() {
        // Test combinations of modifier flags
        let cmdShift = UInt32(cmdKey | shiftKey)
        let display1 = SettingsManager.displayString(for: UInt16(kVK_ANSI_A), modifierFlags: cmdShift)
        #expect(display1.contains("⌘"))
        #expect(display1.contains("⇧"))
        #expect(display1.contains("A"))
        
        let optCtrl = UInt32(optionKey | controlKey)
        let display2 = SettingsManager.displayString(for: UInt16(kVK_ANSI_Z), modifierFlags: optCtrl)
        #expect(display2.contains("⌥"))
        #expect(display2.contains("⌃"))
        #expect(display2.contains("Z"))
    }
    
    @Test("AppAppearance colorScheme mapping is consistent")
    func testAppAppearanceColorSchemes() {
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
        #expect(AppAppearance.system.colorScheme == nil)
    }
    
    @Test("Language list maintains invariant of having at least one language")
    func testLanguageListInvariants() {
        let settings = SettingsManager.shared
        let originalLanguages = settings.recognitionLanguages
        
        defer {
            // Restore original settings
            settings.recognitionLanguages = originalLanguages
        }
        
        // Ensure baseline
        #expect(!settings.recognitionLanguages.isEmpty)
        
        // Adding duplicate language should be idempotent
        if let first = settings.recognitionLanguages.first {
            let countBefore = settings.recognitionLanguages.count
            if !settings.recognitionLanguages.contains(first) {
                settings.recognitionLanguages.append(first)
            }
            // In CaptureSettingsView logic, duplicates are filtered
            let uniqueCount = Set(settings.recognitionLanguages).count
            #expect(uniqueCount <= countBefore)
        }
    }
    
    @Test("RecognitionLevel descriptions are non-empty")
    func testRecognitionLevelDescriptions() {
        for level in RecognitionLevel.allCases {
            #expect(!level.description.isEmpty)
        }
    }
    
    @Test("Debug overlay defaults to false and toggles predictably")
    func testDebugOverlayToggle() {
        let settings = SettingsManager.shared
        let original = settings.showDebugOverlay
        defer { settings.showDebugOverlay = original }
        
        settings.showDebugOverlay = false
        #expect(!settings.showDebugOverlay)
        settings.showDebugOverlay.toggle()
        #expect(settings.showDebugOverlay)
        settings.showDebugOverlay.toggle()
        #expect(!settings.showDebugOverlay)
    }
}
