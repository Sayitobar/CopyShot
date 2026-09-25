//
//  QuickActionsTests.swift
//  CopyShotTests
//
//  Created by Mac on 25.09.26.
//

import XCTest
@testable import CopyShot

final class QuickActionsTests: XCTestCase {

    func testQuickActionsShortcutInvariants() {
        let actions = QuickAction.defaultActions
        XCTAssertFalse(actions.isEmpty, "Default actions should not be empty")
        
        var seenNumbers = Set<Int>()
        for action in actions {
            XCTAssertTrue((1...9).contains(action.shortcutNumber), "Shortcut number \(action.shortcutNumber) out of 1...9 range")
            XCTAssertFalse(seenNumbers.contains(action.shortcutNumber), "Duplicate shortcut number \(action.shortcutNumber)")
            seenNumbers.insert(action.shortcutNumber)
        }
    }

    func testPdfLineBreakStripping() {
        guard let action = QuickAction.defaultActions.first(where: { $0.id == "pdf_strip" }) else {
            XCTFail("Missing pdf_strip action")
            return
        }
        
        let input = "This is a single\nsentence split across lines.\n\nThis is paragraph two\nwith another line."
        let result = action.transform(input)
        let expected = "This is a single sentence split across lines.\n\nThis is paragraph two with another line."
        XCTAssertEqual(result, expected)
    }

    func testCaseTransformations() {
        guard let upper = QuickAction.defaultActions.first(where: { $0.id == "uppercase" }),
              let lower = QuickAction.defaultActions.first(where: { $0.id == "lowercase" }),
              let title = QuickAction.defaultActions.first(where: { $0.id == "title_case" }),
              let toggle = QuickAction.defaultActions.first(where: { $0.id == "toggle_case" }) else {
            XCTFail("Missing case action")
            return
        }
        
        let input = "Hello World"
        XCTAssertEqual(upper.transform(input), "HELLO WORLD")
        XCTAssertEqual(lower.transform(input), "hello world")
        XCTAssertEqual(title.transform("hello world"), "Hello World")
        XCTAssertEqual(toggle.transform("Hello World"), "hELLO wORLD")
    }

    func testSentenceCase() {
        guard let action = QuickAction.defaultActions.first(where: { $0.id == "sentence_case" }) else {
            XCTFail("Missing sentence_case action")
            return
        }
        
        let input = "this is first. this is second."
        let result = action.transform(input)
        XCTAssertEqual(result, "This is first. This is second.")
    }
}
