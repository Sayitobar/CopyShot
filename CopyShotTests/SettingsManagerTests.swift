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

    @Test("Capture mode and MFR unload defaults are correctly configured")
    func testCaptureModeAndMFRUnloadDefaults() throws {
        let suite = "CopyShotTests.captureModeDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.defaultCaptureMode == .standardOCR)
        #expect(settings.captureModeBehavior == .always)
        #expect(settings.captureModeResetTimeoutMinutes == 15)
        #expect(settings.lastUsedCaptureMode == .standardOCR)
        #expect(settings.mfrUnloadPolicy == .defaultTimeout)
        #expect(settings.mfrUnloadPolicy.rawSeconds == 60)
    }

    @Test("Capture mode and MFR unload policy persist across instances")
    func testCaptureModeSettingsPersistence() throws {
        let suite = "CopyShotTests.captureModePersist.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        settings.defaultCaptureMode = .latex
        settings.captureModeBehavior = .returnToDefaultAfterTimeout
        settings.captureModeResetTimeoutMinutes = 30
        settings.mfrUnloadPolicy = .never
        settings.recordCaptureModeUsed(.qrBarcode)

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.defaultCaptureMode == .latex)
        #expect(reloaded.captureModeBehavior == .returnToDefaultAfterTimeout)
        #expect(reloaded.captureModeResetTimeoutMinutes == 30)
        #expect(reloaded.mfrUnloadPolicy == .never)
        #expect(reloaded.lastUsedCaptureMode == .qrBarcode)
        #expect(reloaded.lastCaptureDate != nil)
    }

    @Test("initialCaptureMode correctly implements Always behavior")
    func testCaptureModeBehaviorAlways() throws {
        let suite = "CopyShotTests.behaviorAlways.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        settings.defaultCaptureMode = .standardOCR
        settings.captureModeBehavior = .always
        settings.recordCaptureModeUsed(.latex)

        // Under 'always', it must return defaultCaptureMode even though LaTeX was last used
        #expect(settings.initialCaptureMode() == .standardOCR)
    }

    @Test("initialCaptureMode correctly implements Stick to Last Selected behavior")
    func testCaptureModeBehaviorRememberLast() throws {
        let suite = "CopyShotTests.behaviorRememberLast.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        settings.defaultCaptureMode = .standardOCR
        settings.captureModeBehavior = .rememberLast
        settings.recordCaptureModeUsed(.table)

        #expect(settings.initialCaptureMode() == .table)
    }

    @Test("initialCaptureMode correctly implements Return to Default after Inactivity")
    func testCaptureModeBehaviorReturnToDefaultAfterTimeout() throws {
        let suite = "CopyShotTests.behaviorTimeout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        settings.defaultCaptureMode = .standardOCR
        settings.captureModeBehavior = .returnToDefaultAfterTimeout
        settings.captureModeResetTimeoutMinutes = 15

        let baseTime = Date()
        settings.recordCaptureModeUsed(.latex, date: baseTime)

        // 10 minutes later (< 15 min): sticks to last used (.latex)
        let withinTimeout = baseTime.addingTimeInterval(10 * 60)
        #expect(settings.initialCaptureMode(currentTime: withinTimeout) == .latex)

        // 16 minutes later (> 15 min): reverts to default (.standardOCR)
        let expiredTime = baseTime.addingTimeInterval(16 * 60)
        #expect(settings.initialCaptureMode(currentTime: expiredTime) == .standardOCR)
    }

    @Test("ModelUnloadPolicy preset stops and display titles format properly")
    func testModelUnloadPolicyStopsAndTitles() {
        #expect(ModelUnloadPolicy.immediately.displayTitle == "Immediately")
        #expect(ModelUnloadPolicy.immediately.isImmediately)
        #expect(ModelUnloadPolicy.immediately.timeout == 0)

        #expect(ModelUnloadPolicy.never.displayTitle == "Never")
        #expect(ModelUnloadPolicy.never.isNever)
        #expect(ModelUnloadPolicy.never.timeout == nil)

        let sixtySec = ModelUnloadPolicy(rawSeconds: 60)
        #expect(sixtySec.displayTitle == "1 minute (Default)")
        #expect(sixtySec.timeout == 60)

        let fiveMin = ModelUnloadPolicy(rawSeconds: 300)
        #expect(fiveMin.displayTitle == "5 minutes")

        let oneHour = ModelUnloadPolicy(rawSeconds: 3600)
        #expect(oneHour.displayTitle == "1 hour")

        #expect(ModelUnloadPolicy.immediately.closestStopIndex == 0)
        #expect(ModelUnloadPolicy.never.closestStopIndex == ModelUnloadPolicy.presetStops.count - 1)
        #expect(ModelUnloadPolicy.defaultTimeout.closestStopIndex == 3)
    }

    @Test("Recognition prewarming defaults to enabled and persists across instances")
    func testPrewarmRecognitionSetting() throws {
        let suite = "CopyShotTests.prewarmSetting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Initial default should be true
        let settings = SettingsManager(defaults: defaults)
        #expect(settings.prewarmRecognition == true)

        // Mutating to false should persist
        settings.prewarmRecognition = false
        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.prewarmRecognition == false)
    }
}
