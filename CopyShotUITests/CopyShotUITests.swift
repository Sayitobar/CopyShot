//
//  CopyShotUITests.swift
//  CopyShotUITests
//
//  Created by Mac on 14.06.25.
//

import XCTest

final class CopyShotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowOpensAndSwitchesTabs() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-show-settings")
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

}
