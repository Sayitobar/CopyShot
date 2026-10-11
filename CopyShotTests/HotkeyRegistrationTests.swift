import Carbon
import XCTest
@testable import CopyShot

final class HotkeyRegistrationTests: XCTestCase {
    @MainActor
    func testFailedResetRestoresPersistedWorkingShortcutAndKeepsVisibleError() async throws {
        let suite = "CopyShotTests.shortcutReset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        let active = HotkeyConfig(keyCode: UInt16(kVK_ANSI_D), modifierFlags: UInt32(controlKey | optionKey), displayString: "⌃⌥D")
        settings.captureHotkey = active
        let registration = HotkeyRegistration(register: { config in
            if config == .defaultCapture { throw HotkeyRegistrationError.unavailable(-9878) }
            return EventHotKeyRef(bitPattern: 1)!
        }, unregister: { _ in })
        let manager = HotkeyManager(settings: settings, registration: registration)
        manager.registerHotkeys()
        settings.resetHotkeysToDefaults()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(settings.captureHotkey, active)
        XCTAssertEqual(SettingsManager(defaults: defaults).captureHotkey, active)
        XCTAssertNotNil(manager.registrationError)
        try manager.setCaptureHotkey(active)
        XCTAssertNil(manager.registrationError)
    }

    func testFailedReplacementKeepsTheRegisteredShortcutAndSameCombinationIsANoOp() throws {
        var registered: [HotkeyConfig] = []
        var unregistered: [EventHotKeyRef] = []
        let handle = try XCTUnwrap(EventHotKeyRef(bitPattern: 1))
        let registrar = HotkeyRegistration(register: { config in
            registered.append(config)
            if config.keyCode == UInt16(kVK_ANSI_X) { throw HotkeyRegistrationError.unavailable(-9878) }
            return handle
        }, unregister: { unregistered.append($0) })
        try registrar.replace(with: .defaultCapture)
        let conflict = HotkeyConfig(keyCode: UInt16(kVK_ANSI_X), modifierFlags: UInt32(cmdKey), displayString: "⌘X")
        XCTAssertThrowsError(try registrar.replace(with: conflict))
        XCTAssertEqual(registrar.activeConfig, .defaultCapture)
        XCTAssertTrue(unregistered.isEmpty)
        let same = HotkeyConfig(keyCode: HotkeyConfig.defaultCapture.keyCode,
                                modifierFlags: HotkeyConfig.defaultCapture.modifierFlags, displayString: "Different label")
        try registrar.replace(with: same)
        XCTAssertEqual(registered.count, 2)
        let replacement = HotkeyConfig(keyCode: UInt16(kVK_ANSI_D), modifierFlags: UInt32(controlKey | optionKey), displayString: "⌃⌥D")
        try registrar.replace(with: replacement)
        XCTAssertEqual(registrar.activeConfig, replacement)
        XCTAssertEqual(unregistered, [handle])
    }

    func testUnmodifiedAndShiftOnlyKeysCannotBecomeGlobalShortcuts() {
        var attempts = 0
        let registrar = HotkeyRegistration(register: { _ in attempts += 1; return EventHotKeyRef(bitPattern: 1)! }, unregister: { _ in })
        for modifiers: UInt32 in [0, UInt32(shiftKey)] {
            XCTAssertThrowsError(try registrar.replace(with: .init(keyCode: 0, modifierFlags: modifiers, displayString: "A")))
        }
        XCTAssertEqual(attempts, 0)
        XCTAssertNil(registrar.activeConfig)
    }
}
