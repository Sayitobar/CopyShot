//
//  CopyShotUITests.swift
//  CopyShotUITests
//
//  Created by Mac on 14.06.25.
//

import XCTest
import AppKit

final class CopyShotUITests: XCTestCase {
    @MainActor
    func testMissingMFRModelOpensNativeDownloaderFromLaTeXSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launchEnvironment["COPYSHOT_UI_TEST_APPEARANCE"] = "Light"
        app.launchEnvironment["COPYSHOT_MFR_MODEL_DIR"] = NSTemporaryDirectory() + "CopyShot.MissingMFR.\(UUID().uuidString)"
        app.launch()
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.buttons["settings-tab-Capture"].click()
        settings.buttons["capture-mode-latex"].click()
        let download = settings.buttons["settings-mfr-model"]
        XCTAssertTrue(download.waitForExistence(timeout: 3))
        download.click()
        let downloader = app.windows["LaTeX Model"]
        XCTAssertTrue(downloader.waitForExistence(timeout: 3))
        XCTAssertTrue(downloader.buttons["mfr-download-start"].exists)
        XCTAssertTrue(downloader.staticTexts["Pix2Text MFR 1.5 · 120 MB"].exists)
        let screenshot = XCTAttachment(screenshot: downloader.screenshot())
        screenshot.name = "Native MFR Model Download Prompt"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        downloader.buttons["Cancel"].click()
        XCTAssertFalse(downloader.exists)
        XCTAssertTrue(settings.exists)
        download.click()
        XCTAssertTrue(downloader.waitForExistence(timeout: 3))
        downloader.buttons["Cancel"].click()
    }

    @MainActor
    func testSelectiveResetCanBeCancelledAndOnlyResetsChosenPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launchEnvironment["COPYSHOT_UI_TEST_APPEARANCE"] = "Light"
        app.launch()
        let window = app.windows["Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.buttons["settings-reset"].waitForExistence(timeout: 3))
        window.buttons["settings-tab-Notifications"].click()
        let preview = window.textFields["settings-notifications-preview-limit"]
        preview.click()
        preview.typeKey("a", modifierFlags: .command)
        preview.typeText("12")
        preview.typeKey(.return, modifierFlags: [])
        window.buttons["settings-tab-Quick Actions"].click()
        window.checkBoxes["settings-quick-actions-master"].click()
        window.buttons["settings-tab-General"].click()
        let originalHeight = settledWindowHeight(window)
        let generalScreenshot = XCTAttachment(screenshot: window.screenshot())
        generalScreenshot.name = "General Reset Link"
        generalScreenshot.lifetime = .keepAlways
        add(generalScreenshot)
        window.buttons["settings-reset"].click()
        let resetWindow = app.windows["Reset Settings"]
        XCTAssertTrue(resetWindow.waitForExistence(timeout: 3))
        XCTAssertFalse(app.sheets.firstMatch.exists)
        let reset = resetWindow.buttons["settings-reset-confirm"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        XCTAssertFalse(reset.isEnabled)
        resetWindow.checkBoxes["settings-reset-page-notifications"].click()
        let resetScreenshot = XCTAttachment(screenshot: resetWindow.screenshot())
        resetScreenshot.name = "Selective Settings Reset"
        resetScreenshot.lifetime = .keepAlways
        add(resetScreenshot)
        resetWindow.buttons["settings-reset-cancel"].click()
        XCTAssertFalse(resetWindow.exists)
        window.buttons["settings-tab-Notifications"].click()
        XCTAssertEqual(preview.value as? String, "12")
        window.buttons["settings-tab-General"].click()
        window.buttons["settings-reset"].click()
        XCTAssertTrue(resetWindow.waitForExistence(timeout: 3))
        XCTAssertFalse(reset.isEnabled)
        resetWindow.checkBoxes["settings-reset-page-notifications"].click()
        reset.click()
        XCTAssertFalse(resetWindow.exists)
        XCTAssertEqual(window.frame.height, originalHeight, accuracy: 1)
        XCTAssertEqual(String(describing: window.radioButtons["Light"].value ?? ""), "1")
        window.buttons["settings-tab-Notifications"].click()
        XCTAssertEqual(preview.value as? String, "50")
        window.buttons["settings-tab-Quick Actions"].click()
        XCTAssertEqual(String(describing: window.checkBoxes["settings-quick-actions-master"].value ?? ""), "0")
    }


    @MainActor
    func testCustomURLActionsCanBeCreatedEditedWhileDisabledAndDeleted() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing-show-settings"]
            app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
            app.launchEnvironment["COPYSHOT_UI_TEST_APPEARANCE"] = appearance
            app.launch()
            let window = app.windows["Settings"]
            XCTAssertTrue(window.waitForExistence(timeout: 10))
            window.buttons["settings-tab-Quick Actions"].click()
            let addButton = window.buttons["qa-add-url"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 3))
            let initialHeight = settledWindowHeight(window)
            addButton.click()
            let title = window.textFields["qa-url-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 3))
            title.click()
            title.typeText("A long custom action title that wraps naturally without changing window bounds")
            let template = window.textFields["qa-url-template"]
            template.click()
            template.typeText("https://example.com/?q={text}")
            window.buttons["qa-url-save"].click()
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
            let edit = window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "qa-edit-url-")).firstMatch
            for _ in 0..<8 where !edit.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            XCTAssertTrue(edit.exists)
            let actionID = "custom.url." + edit.identifier.replacingOccurrences(of: "qa-edit-url-", with: "")
            XCTAssertTrue(window.descendants(matching: .any)["qa-custom-indicator-\(actionID)"].exists)
            XCTAssertFalse(window.buttons["qa-configure-\(actionID)"].exists)
            XCTAssertFalse(window.descendants(matching: .any)["qa-custom-installation-help"].exists)
            window.buttons["qa-custom-expand-\(actionID)"].click()
            XCTAssertTrue(window.descendants(matching: .any)["qa-custom-details-\(actionID)"].exists)
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
            window.buttons["qa-custom-expand-\(actionID)"].click()
            edit.click()
            XCTAssertTrue(title.waitForExistence(timeout: 3))
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
            let cancel = window.buttons["qa-url-cancel"]
            for _ in 0..<8 where !cancel.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200)
            let editorScreenshot = XCTAttachment(screenshot: window.screenshot())
            editorScreenshot.name = "Custom Action Editor \(appearance)"
            editorScreenshot.lifetime = .keepAlways
            add(editorScreenshot)
            cancel.click()
            let delete = window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "qa-delete-url-")).firstMatch
            for _ in 0..<8 where !delete.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            delete.click()
            window.buttons["Cancel"].click()
            XCTAssertTrue(edit.exists)
            delete.click()
            window.buttons["Delete"].click()
            XCTAssertFalse(edit.exists)
            XCTAssertFalse(window.descendants(matching: .any)["qa-row-standardOCR-\(actionID)"].exists)
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
            let help = window.buttons["qa-custom-help"]
            for _ in 0..<8 where !help.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            help.click()
            XCTAssertTrue(window.descendants(matching: .any)["qa-custom-installation-help"].exists)
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
            help.click()
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Custom Actions \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    private func settledWindowHeight(_ window: XCUIElement) -> CGFloat {
        var height = window.frame.height
        var stableObservations = 0
        let deadline = Date().addingTimeInterval(5)
        while stableObservations < 5, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let next = window.frame.height
            stableObservations = abs(next - height) < 0.5 ? stableObservations + 1 : 0
            height = next
        }
        return height
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testManyCustomActionsScrollWithinStableWindowBounds() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launch()
        let window = app.windows["Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings-tab-Quick Actions"].click()
        let addButton = window.buttons["qa-add-url"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        let initialHeight = settledWindowHeight(window)
        for index in 1...12 {
            for _ in 0..<20 where !addButton.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            XCTAssertTrue(addButton.isHittable)
            addButton.click()
            let title = window.textFields["qa-url-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 3))
            for _ in 0..<20 where !title.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            title.click()
            title.typeText("Custom action \(index)")
            let template = window.textFields["qa-url-template"]
            template.click()
            template.typeText("https://example.com/?q={text}")
            let save = window.buttons["qa-url-save"]
            for _ in 0..<20 where !save.isHittable { window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -200) }
            save.click()
            XCTAssertEqual(window.frame.height, initialHeight, accuracy: 1)
        }
        XCTAssertEqual(window.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "qa-edit-url-")).count, 12)
        XCTAssertTrue(window.scrollViews.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Many Custom Actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        let heading = window.descendants(matching: .any)["qa-catalog-heading"]
        let selector = window.descendants(matching: .any)["qa-mode-switcher"]
        XCTAssertTrue(heading.exists)
        XCTAssertLessThan(heading.frame.maxY, selector.frame.minY)
        let initialHeight = settledWindowHeight(window)
        for (mode, action) in [("qrBarcode", "copy_raw"), ("latex", "search_math"), ("table", "table_markdown"), ("standardOCR", "join_lines")] {
            let segment = window.buttons["qa-mode-\(mode)"]
            segment.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)).click()
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
        // Accessibility coordinates start at the primary screen's top-left. The runner's
        // main screen can differ from the app's destination on a multi-display desktop.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let hudCenter = CGPoint(x: hud.frame.midX, y: primaryTop - hud.frame.midY)
        let destinationScreen = NSScreen.screens.first { $0.frame.contains(hudCenter) }
        XCTAssertNotNil(destinationScreen)
        XCTAssertLessThanOrEqual(submenu.frame.height, destinationScreen?.visibleFrame.height ?? submenu.frame.height)
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
