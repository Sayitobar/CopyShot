//
//  CopyShotUITests.swift
//  CopyShotUITests
//
//  Created by Mac on 14.06.25.
//

import XCTest
import AppKit

final class CopyShotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowOpensAndSwitchesTabs() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-show-settings")
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launch()
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        let quickActionsTab = settingsWindow.buttons["settings-tab-Quick Actions"]
        XCTAssertTrue(quickActionsTab.exists)
        quickActionsTab.click()
        XCTAssertTrue(
            settingsWindow.descendants(matching: .any)["settings-quick-actions-master"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testModeCatalogsAndDisclosureKeepWindowHeightStable() throws {
        try verifySettingsLayout(appearance: "Light")
    }

    @MainActor
    func testDarkModeCatalogsAndDisclosureKeepWindowHeightStable() throws {
        try verifySettingsLayout(appearance: "Dark")
    }

    @MainActor
    private func verifySettingsLayout(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-show-settings")
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launchEnvironment["COPYSHOT_UI_TEST_APPEARANCE"] = appearance
        app.launch()
        let window = app.windows["Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings-tab-Quick Actions"].click()
        XCTAssertTrue(window.descendants(matching: .any)["qa-mode-switcher"].waitForExistence(timeout: 5))
        let initialHeight = window.frame.height
        for (mode, action) in [("qrBarcode", "copy_raw"), ("latex", "search_math"), ("table", "table_markdown"), ("standardOCR", "join_lines")] {
            window.buttons["qa-mode-\(mode)"].click()
            XCTAssertTrue(window.descendants(matching: .any)["qa-row-\(mode)-\(action)"].waitForExistence(timeout: 3))
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Quick Actions \(appearance) \(mode)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let ocrToggle = window.descendants(matching: .any)["qa-enabled-standardOCR-join_lines"]
        ocrToggle.click()
        window.buttons["qa-mode-table"].click()
        window.buttons["qa-configure-table_markdown"].click()
        XCTAssertTrue(window.descendants(matching: .any)["qa-markdown-header"].waitForExistence(timeout: 3))
        XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
        window.buttons["qa-mode-standardOCR"].click()
        XCTAssertEqual((window.descendants(matching: .any)["qa-enabled-standardOCR-join_lines"].value as? NSNumber)?.intValue, 0)
    }

    @MainActor
    func testLongBarcodeSubmenuScrollsWithoutInvalidShortcuts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings", "--ui-testing-qa-fixture"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launch()
        let hud = app.descendants(matching: .any)["qa-hud-content"]
        XCTAssertTrue(hud.waitForExistence(timeout: 10))
        hud.hover()
        app.descendants(matching: .any)["qa-shelf-handle"].hover()
        let parent = app.buttons["qa-action-search_web"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        parent.hover()
        let first = app.buttons["qa-action-barcode_web_0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.hover()
        let submenu = app.descendants(matching: .any)["qa-submenu-content"]
        XCTAssertLessThanOrEqual(submenu.frame.height, NSScreen.main?.visibleFrame.height ?? submenu.frame.height)
        XCTAssertEqual(first.value as? String, "Shortcut 1")
        let last = app.buttons["qa-action-barcode_web_35"]
        XCTAssertEqual(last.value as? String, "No numeric shortcut")
        for _ in 0..<6 where !last.isHittable {
            submenu.scroll(byDeltaX: 0, deltaY: -500)
        }
        XCTAssertTrue(last.isHittable)
        let screenshot = XCTAttachment(screenshot: submenu.screenshot())
        screenshot.name = "Scrolled barcode submenu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
