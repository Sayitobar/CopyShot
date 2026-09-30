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
    
    // MARK: - Settings & Configuration Tests
    
    func testQuickActionsConfigSerialization() throws {
        var config = QuickActionsConfig()
        config.isEnabled = false
        config.actionOrder = ["search_web", "join_lines", "change_case"]
        config.disabledActionIds = ["join_lines"]
        config.searchEngine = .duckDuckGo
        config.defaultTranslateLanguage = "de"
        config.showNumericShortcuts = false
        config.playHapticsOnHover = false
        config.subActionOrder = ["change_case": ["uppercase", "lowercase"]]
        config.disabledSubActionIds = ["change_case": ["toggle_case"]]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(QuickActionsConfig.self, from: data)
        
        XCTAssertEqual(decoded, config)
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.actionOrder, ["search_web", "join_lines", "change_case"])
        XCTAssertEqual(decoded.disabledActionIds, ["join_lines"])
        XCTAssertEqual(decoded.searchEngine, .duckDuckGo)
        XCTAssertEqual(decoded.defaultTranslateLanguage, "de")
        XCTAssertFalse(decoded.showNumericShortcuts)
        XCTAssertFalse(decoded.playHapticsOnHover)
        XCTAssertEqual(decoded.subActionOrder["change_case"], ["uppercase", "lowercase"])
        XCTAssertEqual(decoded.disabledSubActionIds["change_case"], ["toggle_case"])
    }
    
    func testDisabledQuickActionsConfigProducesNoActions() {
        var config = QuickActionsConfig()
        config.isEnabled = false
        
        let actions = QuickAction.actions(for: "Sample text", config: config)
        XCTAssertTrue(actions.isEmpty, "When Quick Actions is disabled globally, no actions should be generated")
    }
    
    func testActionReorderingAndSequentialShortcuts() {
        var config = QuickActionsConfig()
        // Custom order: search_web first, then join_lines, then change_case
        config.actionOrder = ["search_web", "join_lines", "change_case"]
        
        let actions = QuickAction.actions(for: "Sample text", config: config)
        XCTAssertEqual(actions.map(\.id), ["search_web", "join_lines", "change_case"])
        XCTAssertEqual(actions.map(\.shortcutNumber), [1, 2, 3], "Shortcuts must be sequentially re-indexed 1...N based on order")
    }
    
    func testDisablingSpecificActions() {
        var config = QuickActionsConfig()
        config.actionOrder = ["change_case", "join_lines", "search_web", "translate"]
        config.disabledActionIds = ["join_lines"]
        
        let actions = QuickAction.actions(for: "Sample text", config: config)
        let ids = actions.map(\.id)
        XCTAssertFalse(ids.contains("join_lines"), "Disabled action must not appear in generated actions")
        
        // Ensure sequential shortcut numbering is maintained without gaps
        for (idx, action) in actions.enumerated() {
            XCTAssertEqual(action.shortcutNumber, idx + 1, "Shortcut number must be sequential with no holes")
        }
    }
    
    func testSubActionOrderingAndFiltering() {
        var config = QuickActionsConfig()
        // Invert case transforms order and disable toggle_case
        config.subActionOrder["change_case"] = ["sentence_case", "uppercase", "lowercase", "title_case"]
        config.disabledSubActionIds["change_case"] = ["uppercase"]
        
        let actions = QuickAction.actions(for: "Sample text", config: config)
        guard let changeCase = actions.first(where: { $0.id == "change_case" }),
              let subs = changeCase.subActions else {
            XCTFail("Missing change_case action")
            return
        }
        
        let subIds = subs.map(\.id)
        XCTAssertEqual(subIds, ["sentence_case", "lowercase", "title_case"])
        XCTAssertFalse(subIds.contains("uppercase"))
        XCTAssertEqual(subs.map(\.shortcutNumber), [1, 2, 3], "Sub-action shortcuts must be sequentially re-indexed")
    }
    
    func testSearchEnginesURLGeneration() {
        let query = "hello world"
        
        let googleURL = SearchEngine.google.searchURL(for: query)
        XCTAssertEqual(googleURL?.absoluteString, "https://www.google.com/search?q=hello%20world")
        
        let ddgURL = SearchEngine.duckDuckGo.searchURL(for: query)
        XCTAssertEqual(ddgURL?.absoluteString, "https://duckduckgo.com/?q=hello%20world")
        
        let bingURL = SearchEngine.bing.searchURL(for: query)
        XCTAssertEqual(bingURL?.absoluteString, "https://www.bing.com/search?q=hello%20world")
        
        let kagiURL = SearchEngine.kagi.searchURL(for: query)
        XCTAssertEqual(kagiURL?.absoluteString, "https://kagi.com/search?q=hello%20world")
        
        let braveURL = SearchEngine.brave.searchURL(for: query)
        XCTAssertEqual(braveURL?.absoluteString, "https://search.brave.com/search?q=hello%20world")
        
        let ecosiaURL = SearchEngine.ecosia.searchURL(for: query)
        XCTAssertEqual(ecosiaURL?.absoluteString, "https://www.ecosia.org/search?q=hello%20world")
    }

    func testSearchQueryKeepsReservedCharactersInOneValue() {
        for engine in SearchEngine.allCases {
            let url = try? XCTUnwrap(engine.searchURL(for: "red & blue #="))
            let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            XCTAssertEqual(components?.queryItems?.count, 1, "\(engine) must keep punctuation inside q")
            XCTAssertEqual(components?.queryItems?.first?.name, "q")
            XCTAssertEqual(components?.queryItems?.first?.value, "red & blue #=")
        }
    }
    
    func testDefaultTranslateLanguageConfig() {
        if #available(macOS 15.0, *) {
            var config = QuickActionsConfig()
            config.defaultTranslateLanguage = "de"
            
            let actions = QuickAction.actions(for: "Hello world", config: config)
            let translate = actions.first(where: { $0.id == "translate" })
            XCTAssertEqual(translate?.targetLanguageCode, "de")
            XCTAssertEqual(translate?.title, "Translate (to de.)")
            
            // Sub-actions should not include the default language "de"
            let subLangs = translate?.subActions?.compactMap(\.targetLanguageCode) ?? []
            XCTAssertFalse(subLangs.contains("de"), "Sub-actions should offer alternative languages other than default")
            XCTAssertTrue(subLangs.contains("en"), "en should now be in the alternative sub-shelf")
        }
    }
    
    func testResetQuickActionsToDefaults() {
        let suite = "CopyShotTests.quickActions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        
        settings.quickActionsConfig.isEnabled = false
        settings.quickActionsConfig.searchEngine = .kagi
        settings.quickActionsConfig.showNumericShortcuts = false
        
        settings.resetQuickActionsToDefaults()
        
        XCTAssertTrue(settings.quickActionsConfig.isEnabled)
        XCTAssertEqual(settings.quickActionsConfig.searchEngine, .google)
        XCTAssertTrue(settings.quickActionsConfig.showNumericShortcuts)
        XCTAssertEqual(settings.quickActionsConfig.actionOrder, ["change_case", "join_lines", "search_web", "translate"])
    }
    
    @MainActor
    func testTranslationServiceEmptyTextFailsImmediately() {
        let expectation = expectation(description: "Empty translation returns error")
        TranslationService.shared.translate(text: "   ", targetLanguageCode: "es") { result in
            switch result {
            case .success:
                XCTFail("Expected failure for whitespace-only text")
            case .failure(let error as NSError):
                XCTAssertEqual(error.domain, "CopyShot.Translation")
                XCTAssertEqual(error.code, -5)
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2.0)
    }
    
    func testSubShelfViewCreationWithMainShelfHovered() {
        let subActions = [
            QuickAction(id: "sub_1", title: "Sub 1", icon: .typography("S1"), shortcutNumber: 1, transform: { $0 })
        ]
        let view = ActionSubShelfView(
            subActions: subActions,
            accentColor: .blue,
            isMainShelfHovered: true,
            onActionSelected: { _ in }
        )
        XCTAssertTrue(view.isMainShelfHovered)
        
        let viewNotHovered = ActionSubShelfView(
            subActions: subActions,
            accentColor: .blue,
            isMainShelfHovered: false,
            onActionSelected: { _ in }
        )
        XCTAssertFalse(viewNotHovered.isMainShelfHovered)
    }
    
    func testWrapDollarCyclesProperly() {
        let raw = "x^2 + y^2 = z^2"
        let wrappedSingle = QuickActionTransforms.wrapDollar(raw)
        XCTAssertEqual(wrappedSingle, "$x^2 + y^2 = z^2$")
        
        let wrappedDouble = QuickActionTransforms.wrapDollar(wrappedSingle)
        XCTAssertEqual(wrappedDouble, "$$x^2 + y^2 = z^2$$")
        
        let unwrapped = QuickActionTransforms.wrapDollar(wrappedDouble)
        XCTAssertEqual(unwrapped, raw)
    }
    
    func testModeSpecificQuickActions() {
        let config = QuickActionsConfig()
        
        // Standard OCR
        let ocrActions = QuickAction.actions(for: "Hello World", mode: .standardOCR, config: config)
        XCTAssertTrue(ocrActions.contains(where: { $0.id == "change_case" }))
        XCTAssertTrue(ocrActions.contains(where: { $0.id == "join_lines" }))
        
        // QR / Barcode
        let qrActionsURL = QuickAction.actions(for: "https://apple.com", mode: .qrBarcode, config: config)
        XCTAssertEqual(qrActionsURL.count, 1)
        XCTAssertEqual(qrActionsURL.first?.id, "search_web")
        XCTAssertEqual(qrActionsURL.first?.title, "Open URL")
        XCTAssertEqual(qrActionsURL.first?.shortcutNumber, 1)
        
        let qrActionsText = QuickAction.actions(for: "1234567890", mode: .qrBarcode, config: config)
        XCTAssertEqual(qrActionsText.count, 1)
        XCTAssertEqual(qrActionsText.first?.id, "search_web")
        XCTAssertEqual(qrActionsText.first?.title, "Search Web")
        XCTAssertEqual(qrActionsText.first?.shortcutNumber, 1)
        
        // LaTeX
        let latexActions = QuickAction.actions(for: "E = mc^2", mode: .latex, config: config)
        XCTAssertEqual(latexActions.count, 1)
        XCTAssertEqual(latexActions.first?.id, "latex_wrap_dollar")
        XCTAssertEqual(latexActions.first?.title, "Wrap $...$")
        XCTAssertEqual(latexActions.first?.shortcutNumber, 1)
        
        // Table
        let tableActions = QuickAction.actions(for: "A\tB\nC\tD", mode: .table, config: config)
        XCTAssertEqual(tableActions.count, 0)
    }
}

