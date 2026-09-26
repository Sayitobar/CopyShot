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
        
        if #available(macOS 15.0, *) {
            XCTAssertEqual(actions.count, 4, "Expected exactly 4 default actions on macOS 15+ (Change Case, Join Lines, Search/Open, Translate)")
            XCTAssertEqual(actions.map(\.shortcutNumber), [1, 2, 3, 4])
        } else {
            XCTAssertEqual(actions.count, 3, "Expected exactly 3 default actions on macOS 14 (Translate omitted)")
            XCTAssertEqual(actions.map(\.shortcutNumber), [1, 2, 3])
        }
        
        // Slot 1 Sub-actions verification (5 case transforms: 1...5)
        guard let changeCase = actions.first(where: { $0.id == "change_case" }),
              let caseSubs = changeCase.subActions else {
            XCTFail("Missing change_case action or its subActions")
            return
        }
        XCTAssertTrue(changeCase.hasSubmenu)
        XCTAssertEqual(caseSubs.count, 5)
        XCTAssertEqual(caseSubs.map(\.shortcutNumber), [1, 2, 3, 4, 5])
        
        // Slot 4 Sub-actions verification (5 alternative languages: 1...5)
        if #available(macOS 15.0, *) {
            guard let translate = actions.first(where: { $0.id == "translate" }),
                  let translateSubs = translate.subActions else {
                XCTFail("Missing translate action or its subActions")
                return
            }
            XCTAssertTrue(translate.hasSubmenu)
            XCTAssertEqual(translateSubs.count, 5)
            XCTAssertEqual(translateSubs.map(\.shortcutNumber), [1, 2, 3, 4, 5])
        }
    }

    func testActionTitlesAndIcons() {
        let actions = QuickAction.defaultActions
        
        // Slot 1: Change Case
        let changeCase = actions.first(where: { $0.id == "change_case" })
        XCTAssertEqual(changeCase?.title, "Change Case")
        XCTAssertEqual(changeCase?.icon, .system("textformat"))
        XCTAssertEqual(changeCase?.shortcutNumber, 1)
        XCTAssertTrue(changeCase?.hasSubmenu == true)
        
        let subActions = changeCase?.subActions ?? []
        let titleCase = subActions.first(where: { $0.id == "title_case" })
        XCTAssertEqual(titleCase?.title, "Title Case")
        XCTAssertEqual(titleCase?.icon, .typography("Aa"))
        XCTAssertEqual(titleCase?.shortcutNumber, 1)
        
        let uppercase = subActions.first(where: { $0.id == "uppercase" })
        XCTAssertEqual(uppercase?.title, "UPPERCASE")
        XCTAssertEqual(uppercase?.icon, .typography("AA"))
        XCTAssertEqual(uppercase?.shortcutNumber, 2)
        
        let lowercase = subActions.first(where: { $0.id == "lowercase" })
        XCTAssertEqual(lowercase?.title, "lowercase")
        XCTAssertEqual(lowercase?.icon, .typography("aa"))
        XCTAssertEqual(lowercase?.shortcutNumber, 3)
        
        let toggleCase = subActions.first(where: { $0.id == "toggle_case" })
        XCTAssertEqual(toggleCase?.title, "tOGGLE cASE")
        XCTAssertEqual(toggleCase?.icon, .typography("aA"))
        XCTAssertEqual(toggleCase?.shortcutNumber, 4)
        
        let sentenceCase = subActions.first(where: { $0.id == "sentence_case" })
        XCTAssertEqual(sentenceCase?.title, "Sentence case.")
        XCTAssertEqual(sentenceCase?.icon, .system("text.alignleft"))
        XCTAssertEqual(sentenceCase?.shortcutNumber, 5)
        
        // Slot 2: Join Lines
        let join = actions.first(where: { $0.id == "join_lines" })
        XCTAssertEqual(join?.title, "Join Lines")
        XCTAssertEqual(join?.icon, .system("text.line.2.summary"))
        XCTAssertEqual(join?.shortcutNumber, 2)
        XCTAssertFalse(join?.hasSubmenu == true)
        
        // Slot 3: Search Web (Default without URL)
        let searchWeb = actions.first(where: { $0.id == "search_web" })
        XCTAssertEqual(searchWeb?.title, "Search Web")
        XCTAssertEqual(searchWeb?.icon, .system("magnifyingglass"))
        XCTAssertEqual(searchWeb?.shortcutNumber, 3)
        XCTAssertFalse(searchWeb?.hasSubmenu == true)
        
        // Slot 4: Translate (macOS 15+)
        if #available(macOS 15.0, *) {
            let translate = actions.first(where: { $0.id == "translate" })
            XCTAssertEqual(translate?.title, "Translate (to en.)")
            XCTAssertEqual(translate?.icon, .system("translate"))
            XCTAssertEqual(translate?.shortcutNumber, 4)
            XCTAssertEqual(translate?.targetLanguageCode, "en")
            XCTAssertTrue(translate?.hasSubmenu == true)
            
            let langSubs = translate?.subActions ?? []
            XCTAssertEqual(langSubs.count, 5)
            XCTAssertEqual(langSubs.map(\.targetLanguageCode), ["es", "de", "fr", "ja", "zh"])
        }
        
        // Invariant: ActionIconRenderer resolves symbols and typographic templates cleanly
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "text.line.2.summary"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "text.alignleft"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "textformat"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "magnifyingglass"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "safari"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "translate"))
        XCTAssertNotNil(ActionIconRenderer.image(forSymbol: "globe"))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "AA", size: 18))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "Aa", size: 18))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "aa", size: 18))
        XCTAssertNotNil(ActionIconRenderer.typographyImage(text: "aA", size: 18))
    }

    func testDynamicWebActionAndURLDetection() {
        // Valid URL patterns
        let url1 = "https://github.com/Sayitobar/CopyShot"
        let url2 = "http://localhost:3000/api"
        let url3 = "github.com/apple/swift"
        let url4 = "apple.com"
        
        XCTAssertTrue(WebActionHelper.isURL(url1))
        XCTAssertTrue(WebActionHelper.isURL(url2))
        XCTAssertTrue(WebActionHelper.isURL(url3))
        XCTAssertTrue(WebActionHelper.isURL(url4))
        
        // General text patterns (not URLs)
        let text1 = "Hello world"
        let text2 = "Search for CopyShot features"
        let text3 = "let x = 42\nprint(x)"
        
        XCTAssertFalse(WebActionHelper.isURL(text1))
        XCTAssertFalse(WebActionHelper.isURL(text2))
        XCTAssertFalse(WebActionHelper.isURL(text3))
        
        // Dynamic Quick Actions resolution with URL
        let actionsForURL = QuickAction.defaultActions(for: url1)
        let webActionForURL = actionsForURL.first(where: { $0.id == "search_web" })
        XCTAssertEqual(webActionForURL?.title, "Open URL")
        XCTAssertEqual(webActionForURL?.icon, .system("safari"))
        
        // Dynamic Quick Actions resolution with regular text
        let actionsForText = QuickAction.defaultActions(for: text1)
        let webActionForText = actionsForText.first(where: { $0.id == "search_web" })
        XCTAssertEqual(webActionForText?.title, "Search Web")
        XCTAssertEqual(webActionForText?.icon, .system("magnifyingglass"))
        
        // Search URL generation
        let searchURL = WebActionHelper.searchURL(for: "SwiftUI macOS")
        XCTAssertNotNil(searchURL)
        XCTAssertEqual(searchURL?.absoluteString, "https://www.google.com/search?q=SwiftUI%20macOS")
    }

    func testLanguageDetectionAndNaming() {
        // Source language detection via NLLanguageRecognizer
        let french = TranslationService.detectLanguageCode(for: "Bonjour tout le monde, comment allez-vous?")
        XCTAssertEqual(french, "fr")
        
        let german = TranslationService.detectLanguageCode(for: "Guten Tag, wie geht es Ihnen heute?")
        XCTAssertEqual(german, "de")
        
        let spanish = TranslationService.detectLanguageCode(for: "Hola amigo, que tal estás?")
        XCTAssertEqual(spanish, "es")
        
        // Localized language name formatting
        let enName = TranslationService.localizedLanguageName(for: "en")
        XCTAssertFalse(enName.isEmpty)
        
        let esName = TranslationService.localizedLanguageName(for: "es")
        XCTAssertFalse(esName.isEmpty)
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
        guard let changeCase = QuickAction.defaultActions.first(where: { $0.id == "change_case" }),
              let subs = changeCase.subActions,
              let upper = subs.first(where: { $0.id == "uppercase" }),
              let lower = subs.first(where: { $0.id == "lowercase" }),
              let title = subs.first(where: { $0.id == "title_case" }),
              let toggle = subs.first(where: { $0.id == "toggle_case" }) else {
            XCTFail("Missing case action or subActions")
            return
        }
        
        let input = "Hello World"
        XCTAssertEqual(upper.transform(input), "HELLO WORLD")
        XCTAssertEqual(lower.transform(input), "hello world")
        XCTAssertEqual(title.transform("hello world"), "Hello World")
        XCTAssertEqual(toggle.transform("Hello World"), "hELLO wORLD")
        
        // Direct click on changeCase transforms to Title Case
        XCTAssertEqual(changeCase.transform("hello world"), "Hello World")
        
        // Verify DRY transforms enum
        XCTAssertEqual(QuickActionTransforms.toUppercase(input), "HELLO WORLD")
        XCTAssertEqual(QuickActionTransforms.toLowercase(input), "hello world")
        XCTAssertEqual(QuickActionTransforms.toTitleCase("hello world"), "Hello World")
        XCTAssertEqual(QuickActionTransforms.toToggleCase("Hello World"), "hELLO wORLD")
    }

    func testSentenceCase() {
        guard let changeCase = QuickAction.defaultActions.first(where: { $0.id == "change_case" }),
              let subs = changeCase.subActions,
              let action = subs.first(where: { $0.id == "sentence_case" }) else {
            XCTFail("Missing sentence_case sub-action")
            return
        }
        
        let input = "this is first. this is second."
        let result = action.transform(input)
        XCTAssertEqual(result, "This is first. This is second.")
        XCTAssertEqual(QuickActionTransforms.toSentenceCase(input), "This is first. This is second.")
    }
}
