import XCTest

final class OCRInspectionUITests: XCTestCase {
    @MainActor
    func testInspectionStagesRegionsAndAppearance() {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing-show-settings", "--ui-testing-inspection"]
            app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
            app.launchEnvironment["COPYSHOT_UI_TEST_APPEARANCE"] = appearance
            app.launch()
            let window = app.windows["Capture Inspection"]
            XCTAssertTrue(window.waitForExistence(timeout: 10))
            XCTAssertTrue(window.buttons["inspection-stage-original"].exists)
            window.buttons["inspection-stage-monochrome"].click()
            window.buttons["inspection-stage-input"].click()
            window.buttons["inspection-stage-locations"].click()
            window.buttons["inspection-region-2"].click()
            XCTAssertTrue(window.buttons["inspection-box-2"].exists)
            XCTAssertEqual(window.buttons["inspection-region-2"].value as? String, "Selected")
            XCTAssertEqual(window.buttons["inspection-box-2"].value as? String, "Selected")
            window.buttons["inspection-box-1"].click()
            window.buttons["inspection-zoom-in"].click()
            window.buttons["inspection-fit"].click()
            window.buttons["Actual Size"].click()
            XCTAssertEqual(window.staticTexts["inspection-zoom-label"].value as? String, "100% pixels")
            let originalWidth = window.frame.width
            let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.7)).withOffset(CGVector(dx: -1, dy: 0))
            edge.press(forDuration: 0.2, thenDragTo: edge.withOffset(CGVector(dx: -240, dy: 0)))
            XCTAssertLessThan(window.frame.width, originalWidth)
            XCTAssertEqual(window.staticTexts["inspection-zoom-label"].value as? String, "100% pixels")
            window.buttons["inspection-fit"].click()
            let imageShot = XCTAttachment(screenshot: window.screenshot())
            imageShot.name = "Inspection locations \(appearance)"
            imageShot.lifetime = .keepAlways
            add(imageShot)
            window.buttons["inspection-stage-assembled"].click()
            XCTAssertTrue(window.staticTexts["inspection-output"].exists)
            window.buttons["inspection-close"].click()
            XCTAssertFalse(window.exists)
            app.terminate()
        }
    }

    @MainActor
    func testTransformedOutputAndSelectionAtLargeZoom() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings", "--ui-testing-inspection", "--ui-testing-inspection-transformed"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launch()
        let window = app.windows["Capture Inspection"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for _ in 0..<7 { window.buttons["inspection-zoom-in"].click() }
        window.buttons["inspection-region-3"].click()
        XCTAssertEqual(window.buttons["inspection-region-3"].value as? String, "Selected")
        let zoomed = XCTAttachment(screenshot: window.screenshot())
        zoomed.name = "Selected region at large zoom"
        zoomed.lifetime = .keepAlways
        add(zoomed)
        XCTAssertTrue(window.buttons["inspection-box-3"].isHittable)
        window.scrollViews["inspection-image-viewport"].scroll(byDeltaX: 0, deltaY: 1000)
        window.buttons["inspection-region-3"].click()
        XCTAssertTrue(window.buttons["inspection-box-3"].isHittable)
        window.buttons["inspection-stage-transformed"].click()
        let transformed = window.staticTexts["inspection-output"]
        XCTAssertTrue((transformed.value as? String ?? transformed.label).contains("UNDERSTAND EVERY CAPTURE."))
        window.buttons["inspection-stage-assembled"].click()
        let assembled = window.staticTexts["inspection-output"]
        XCTAssertTrue((assembled.value as? String ?? assembled.label).contains("Understand every capture."))
        window.buttons["inspection-close"].click()
    }

    @MainActor
    func testEmptyInspectionRemainsUseful() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings", "--ui-testing-inspection", "--ui-testing-inspection-empty"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launch()
        let window = app.windows["Capture Inspection"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["No text regions recognized"].exists)
        window.buttons["inspection-stage-original"].click()
        window.buttons["inspection-close"].click()
    }

    @MainActor
    func testInspectionQuickActionStartsDisabledAndKeepsOptInAcrossModes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-show-settings"]
        app.launchEnvironment["COPYSHOT_UI_TEST_SETTINGS_SUITE"] = "CopyShot.UITests.\(UUID().uuidString)"
        app.launch()
        let window = app.windows["Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["settings-tab-Quick Actions"].click()
        let toggle = window.descendants(matching: .any)["qa-enabled-standardOCR-inspect_capture"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        toggle.click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        window.buttons["qa-mode-table"].click()
        window.buttons["qa-mode-standardOCR"].click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        app.terminate()
    }
}
