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
        XCTAssertEqual(actions.count, 6, "Expected exactly 6 default actions (QR and LaTeX excluded)")
        
        var seenNumbers = Set<Int>()
        for action in actions {
            XCTAssertTrue((1...9).contains(action.shortcutNumber), "Shortcut number \(action.shortcutNumber) out of 1...9 range")
            XCTAssertFalse(seenNumbers.contains(action.shortcutNumber), "Duplicate shortcut number \(action.shortcutNumber)")
            seenNumbers.insert(action.shortcutNumber)
        }
        
        // Sequential 1...6 verification
        XCTAssertEqual(actions.map(\.shortcutNumber), [1, 2, 3, 4, 5, 6])
    }

    func testActionTitlesAndIcons() {
        let actions = QuickAction.defaultActions
        
        let join = actions.first(where: { $0.id == "join_lines" })
        XCTAssertEqual(join?.title, "Join Lines")
        XCTAssertEqual(join?.icon, .system("text.line.2.summary"))
        XCTAssertEqual(join?.shortcutNumber, 1)
        
        let title = actions.first(where: { $0.id == "title_case" })
        XCTAssertEqual(title?.title, "Title Case")
        XCTAssertEqual(title?.icon, .typography("Aa"))
        XCTAssertEqual(title?.shortcutNumber, 2)
        
        let upper = actions.first(where: { $0.id == "uppercase" })
        XCTAssertEqual(upper?.title, "UPPERCASE")
        XCTAssertEqual(upper?.icon, .typography("AA"))
        XCTAssertEqual(upper?.shortcutNumber, 3)
        
        let lower = actions.first(where: { $0.id == "lowercase" })
        XCTAssertEqual(lower?.title, "lowercase")
        XCTAssertEqual(lower?.icon, .typography("aa"))
        XCTAssertEqual(lower?.shortcutNumber, 4)
        
        let toggle = actions.first(where: { $0.id == "toggle_case" })
        XCTAssertEqual(toggle?.title, "tOGGLE cASE")
        XCTAssertEqual(toggle?.icon, .typography("aA"))
        XCTAssertEqual(toggle?.shortcutNumber, 5)
        
        let sentence = actions.first(where: { $0.id == "sentence_case" })
        XCTAssertEqual(sentence?.title, "Sentence case.")
        XCTAssertEqual(sentence?.icon, .system("text.alignleft"))
        XCTAssertEqual(sentence?.shortcutNumber, 6)
        
        // Invariant: ActionIconRenderer resolves private symbol text.line.2.summary cleanly
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "text.line.2.summary"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "text.alignleft"))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "AA", size: 18))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "Aa", size: 18))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "aa", size: 18))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "aA", size: 18))
    }

    func testJoinLines() {
        guard let action = QuickAction.defaultActions.first(where: { $0.id == "join_lines" }) else {
            XCTFail("Missing join_lines action")
            return
        }
        
        let input = "This is a single\nsentence split across lines.\n\nThis is paragraph two\nwith another line."
        let result = action.transform(input)
        let expected = "This is a single sentence split across lines.\n\nThis is paragraph two with another line."
        XCTAssertEqual(result, expected)
        
        // Also test directly via QuickActionTransforms helper
        XCTAssertEqual(QuickActionTransforms.joinLines(input), expected)
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
        
        // Verify DRY transforms enum
        XCTAssertEqual(QuickActionTransforms.toUppercase(input), "HELLO WORLD")
        XCTAssertEqual(QuickActionTransforms.toLowercase(input), "hello world")
        XCTAssertEqual(QuickActionTransforms.toTitleCase("hello world"), "Hello World")
        XCTAssertEqual(QuickActionTransforms.toToggleCase("Hello World"), "hELLO wORLD")
    }

    func testSentenceCase() {
        guard let action = QuickAction.defaultActions.first(where: { $0.id == "sentence_case" }) else {
            XCTFail("Missing sentence_case action")
            return
        }
        
        let input = "this is first. this is second."
        let result = action.transform(input)
        XCTAssertEqual(result, "This is first. This is second.")
        XCTAssertEqual(QuickActionTransforms.toSentenceCase(input), "This is first. This is second.")
    }
}
