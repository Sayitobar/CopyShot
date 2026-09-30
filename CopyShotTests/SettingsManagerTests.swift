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

    @Test("Explicit zero preview limit is distinct from a missing preference")
    func testZeroPreviewLimitPersists() throws {
        let suite = "CopyShotTests.previewLimit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SettingsManager.previewLimit(from: defaults) == 50)
        defaults.set(0, forKey: SettingsKeys.textPreviewLimit)
        #expect(SettingsManager.previewLimit(from: defaults) == 0)
        #expect(SettingsManager(defaults: defaults).textPreviewLimit == 0)
    }

    @Test("Settings persist across instances in an isolated defaults domain")
    func testSettingsRoundTrip() throws {
        let suite = "CopyShotTests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        settings.recognitionLevel = .fast
        settings.recognitionLanguages = ["de-DE", "en-US"]
        settings.usesLanguageCorrection = false
        settings.textPreviewLimit = 12
        settings.quickActionsConfig.searchEngine = .kagi
        settings.prettifyLatex = true
        settings.fixLatexSyntax = false

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.recognitionLevel == .fast)
        #expect(reloaded.recognitionLanguages == ["de-DE", "en-US"])
        #expect(!reloaded.usesLanguageCorrection)
        #expect(reloaded.textPreviewLimit == 12)
        #expect(reloaded.quickActionsConfig.searchEngine == .kagi)
        #expect(reloaded.prettifyLatex == true)
        #expect(reloaded.fixLatexSyntax == false)
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
    
    @Test("LaTeX default settings are enabled")
    func testLatexDefaultSettings() throws {
        let suite = "CopyShotTests.latexDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        
        let settings = SettingsManager(defaults: defaults)
        #expect(settings.prettifyLatex == true)
        #expect(settings.fixLatexSyntax == true)
    }
}
