//
//  QuickAction.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Visual representation for a Quick Action badge/logo.
enum ActionIcon: Equatable {
    case system(String)
    case typography(String)
}

/// Represents a single quick action executable on recognized capture text.
struct QuickAction: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: ActionIcon
    let shortcutNumber: Int
    let transform: (String) -> String
    let subActions: [QuickAction]?
    let targetLanguageCode: String?
    
    var hasSubmenu: Bool {
        guard let subActions = subActions else { return false }
        return !subActions.isEmpty
    }
    
    init(
        id: String,
        title: String,
        icon: ActionIcon,
        shortcutNumber: Int,
        transform: @escaping (String) -> String = { $0 },
        subActions: [QuickAction]? = nil,
        targetLanguageCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutNumber = shortcutNumber
        self.transform = transform
        self.subActions = subActions
        self.targetLanguageCode = targetLanguageCode
    }
    
    static func == (lhs: QuickAction, rhs: QuickAction) -> Bool {
        lhs.id == rhs.id &&
        lhs.shortcutNumber == rhs.shortcutNumber &&
        lhs.icon == rhs.icon &&
        lhs.title == rhs.title &&
        lhs.targetLanguageCode == rhs.targetLanguageCode &&
        lhs.subActions == rhs.subActions
    }
    
    // MARK: - Dynamic Configuration & Actions Generation
    
    /// Default set of quick actions available for text captures using default configuration.
    static var defaultActions: [QuickAction] {
        defaultActions(for: nil)
    }
    
    /// Returns default quick actions dynamically adjusted for the recognized text using default configuration.
    static func defaultActions(for text: String?) -> [QuickAction] {
        actions(for: text, config: QuickActionsConfig())
    }
    
    /// Constructs ordered, active quick actions based on user configuration and recognized capture text.
    static func actions(for text: String?, config: QuickActionsConfig) -> [QuickAction] {
        guard config.isEnabled else { return [] }
        
        let isURL = text != nil && WebActionHelper.isURL(text!)
        
        // Base sub-actions pool for Change Case
        let allCaseSubActions: [String: QuickAction] = [
            "title_case": QuickAction(
                id: "title_case",
                title: "Title Case",
                icon: .typography("Aa"),
                shortcutNumber: 1,
                transform: QuickActionTransforms.toTitleCase
            ),
            "uppercase": QuickAction(
                id: "uppercase",
                title: "UPPERCASE",
                icon: .typography("AA"),
                shortcutNumber: 2,
                transform: QuickActionTransforms.toUppercase
            ),
            "lowercase": QuickAction(
                id: "lowercase",
                title: "lowercase",
                icon: .typography("aa"),
                shortcutNumber: 3,
                transform: QuickActionTransforms.toLowercase
            ),
            "toggle_case": QuickAction(
                id: "toggle_case",
                title: "tOGGLE cASE",
                icon: .typography("aA"),
                shortcutNumber: 4,
                transform: QuickActionTransforms.toToggleCase
            ),
            "sentence_case": QuickAction(
                id: "sentence_case",
                title: "Sentence case.",
                icon: .system("text.alignleft"),
                shortcutNumber: 5,
                transform: QuickActionTransforms.toSentenceCase
            )
        ]
        
        // Ordered & filtered Change Case sub-actions
        let caseOrder = config.subActionOrder["change_case"] ?? ["title_case", "uppercase", "lowercase", "toggle_case", "sentence_case"]
        let disabledCaseIds = Set(config.disabledSubActionIds["change_case"] ?? [])
        let activeCaseSubActions: [QuickAction] = caseOrder
            .filter { !disabledCaseIds.contains($0) }
            .compactMap { allCaseSubActions[$0] }
            .enumerated()
            .map { index, action in
                QuickAction(
                    id: action.id,
                    title: action.title,
                    icon: action.icon,
                    shortcutNumber: index + 1,
                    transform: action.transform
                )
            }
        
        // Translation sub-actions pool
        var allTranslateSubActions: [String: QuickAction] = [:]
        for lang in TranslationTargetLanguage.supportedLanguages {
            allTranslateSubActions["translate_to_\(lang.code)"] = QuickAction(
                id: "translate_to_\(lang.code)",
                title: lang.name,
                icon: .system("globe"),
                shortcutNumber: 1,
                transform: { $0 },
                targetLanguageCode: lang.code
            )
        }
        
        let defaultSubOrder = ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
        var configuredTranslateOrder = config.subActionOrder["translate"] ?? defaultSubOrder
        
        // If configured order contains the default language, swap it with "en" or first available language not in order
        if let defaultIndex = configuredTranslateOrder.firstIndex(of: "translate_to_\(config.defaultTranslateLanguage)") {
            let candidateLangs = ["en", "es", "de", "fr", "ja", "zh"] + TranslationTargetLanguage.supportedLanguages.map(\.code)
            if let replacement = candidateLangs.first(where: { $0 != config.defaultTranslateLanguage && !configuredTranslateOrder.contains("translate_to_\($0)") }) {
                configuredTranslateOrder[defaultIndex] = "translate_to_\(replacement)"
            } else {
                configuredTranslateOrder.remove(at: defaultIndex)
            }
        }
        
        let disabledTranslateIds = Set(config.disabledSubActionIds["translate"] ?? [])
        let activeTranslateSubActions: [QuickAction] = configuredTranslateOrder
            .filter { !disabledTranslateIds.contains($0) && $0 != "translate_to_\(config.defaultTranslateLanguage)" }
            .compactMap { allTranslateSubActions[$0] }
            .enumerated()
            .map { index, action in
                QuickAction(
                    id: action.id,
                    title: action.title,
                    icon: action.icon,
                    shortcutNumber: index + 1,
                    transform: action.transform,
                    targetLanguageCode: action.targetLanguageCode
                )
            }
        
        // Map top-level actions
        var activeActions: [QuickAction] = []
        let disabledActionIds = Set(config.disabledActionIds)
        
        for actionId in config.actionOrder where !disabledActionIds.contains(actionId) {
            let nextShortcutNumber = activeActions.count + 1
            
            switch actionId {
            case "change_case":
                activeActions.append(
                    QuickAction(
                        id: "change_case",
                        title: "Change Case",
                        icon: .system("textformat"),
                        shortcutNumber: nextShortcutNumber,
                        transform: QuickActionTransforms.toTitleCase,
                        subActions: activeCaseSubActions.isEmpty ? nil : activeCaseSubActions
                    )
                )
            case "join_lines":
                activeActions.append(
                    QuickAction(
                        id: "join_lines",
                        title: "Join Lines",
                        icon: .system("text.line.2.summary"),
                        shortcutNumber: nextShortcutNumber,
                        transform: QuickActionTransforms.joinLines
                    )
                )
            case "search_web":
                activeActions.append(
                    QuickAction(
                        id: "search_web",
                        title: isURL ? "Open URL" : "Search Web",
                        icon: isURL ? .system("safari") : .system("magnifyingglass"),
                        shortcutNumber: nextShortcutNumber,
                        transform: { $0 }
                    )
                )
            case "translate":
                if #available(macOS 15.0, *) {
                    activeActions.append(
                        QuickAction(
                            id: "translate",
                            title: "Translate (to \(config.defaultTranslateLanguage).)",
                            icon: .system("translate"),
                            shortcutNumber: nextShortcutNumber,
                            transform: { $0 },
                            subActions: activeTranslateSubActions.isEmpty ? nil : activeTranslateSubActions,
                            targetLanguageCode: config.defaultTranslateLanguage
                        )
                    )
                }
            default:
                break
            }
        }
        
        return activeActions
    }
}

// MARK: - Search Engine Configuration

/// Supported search engines for the Search Web quick action.
enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case google = "Google"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case kagi = "Kagi"
    case brave = "Brave"
    case ecosia = "Ecosia"
    
    var id: String { rawValue }
    
    func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .kagi:
            return URL(string: "https://kagi.com/search?q=\(encoded)")
        case .brave:
            return URL(string: "https://search.brave.com/search?q=\(encoded)")
        case .ecosia:
            return URL(string: "https://www.ecosia.org/search?q=\(encoded)")
        }
    }
}

// MARK: - Translation Target Language

/// Supported translation destination language with localized display name.
struct TranslationTargetLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
    
    static var supportedLanguages: [TranslationTargetLanguage] {
        allKnownSupportedLanguages.map { lang in
            let localizedName = Locale.current.localizedString(forIdentifier: lang.code)
                ?? Locale(identifier: "en").localizedString(forIdentifier: lang.code)
                ?? lang.name
            let displayName = "\(localizedName) (\(lang.code))"
            return TranslationTargetLanguage(code: lang.code, name: displayName)
        }
    }
    
    static let allKnownSupportedLanguages: [TranslationTargetLanguage] = [
        TranslationTargetLanguage(code: "ar", name: "Arabic (ar)"),
        TranslationTargetLanguage(code: "zh", name: "Chinese (zh)"),
        TranslationTargetLanguage(code: "zh-Hant", name: "Chinese, Traditional (zh-Hant)"),
        TranslationTargetLanguage(code: "nl", name: "Dutch (nl)"),
        TranslationTargetLanguage(code: "en", name: "English (en)"),
        TranslationTargetLanguage(code: "fr", name: "French (fr)"),
        TranslationTargetLanguage(code: "de", name: "German (de)"),
        TranslationTargetLanguage(code: "hi", name: "Hindi (hi)"),
        TranslationTargetLanguage(code: "id", name: "Indonesian (id)"),
        TranslationTargetLanguage(code: "it", name: "Italian (it)"),
        TranslationTargetLanguage(code: "ja", name: "Japanese (ja)"),
        TranslationTargetLanguage(code: "ko", name: "Korean (ko)"),
        TranslationTargetLanguage(code: "pl", name: "Polish (pl)"),
        TranslationTargetLanguage(code: "pt", name: "Portuguese (pt)"),
        TranslationTargetLanguage(code: "ru", name: "Russian (ru)"),
        TranslationTargetLanguage(code: "es", name: "Spanish (es)"),
        TranslationTargetLanguage(code: "th", name: "Thai (th)"),
        TranslationTargetLanguage(code: "tr", name: "Turkish (tr)"),
        TranslationTargetLanguage(code: "uk", name: "Ukrainian (uk)"),
        TranslationTargetLanguage(code: "vi", name: "Vietnamese (vi)")
    ]
}

// MARK: - Quick Actions Configuration Model

/// Unified configuration for Quick Action ordering, visibility, and action-specific parameters.
struct QuickActionsConfig: Codable, Equatable {
    var isEnabled: Bool = true
    var actionOrder: [String] = ["change_case", "join_lines", "search_web", "translate"]
    var disabledActionIds: [String] = []
    
    // Sub-actions ordering & visibility
    var subActionOrder: [String: [String]] = [
        "change_case": ["title_case", "uppercase", "lowercase", "toggle_case", "sentence_case"],
        "translate": ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
    ]
    var disabledSubActionIds: [String: [String]] = [:]
    
    // Action-specific parameters
    var searchEngine: SearchEngine = .google
    var defaultTranslateLanguage: String = "en"
    
    // Ergonomics & Preferences
    var showNumericShortcuts: Bool = true
    var playHapticsOnHover: Bool = true
}

// MARK: - Action Metadata Registry

/// Declarative metadata for built-in Quick Actions, utilized by the Settings configuration interface.
struct ActionMetadata: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let icon: ActionIcon
    let hasSubActions: Bool
    let hasParameters: Bool
    
    static var allActions: [ActionMetadata] {
        var actions: [ActionMetadata] = [
            ActionMetadata(
                id: "change_case",
                title: "Change Case",
                description: "Format text into Title Case, UPPERCASE, lowercase, and more.",
                icon: .system("textformat"),
                hasSubActions: true,
                hasParameters: false
            ),
            ActionMetadata(
                id: "join_lines",
                title: "Join Lines",
                description: "Merge wrapped text into a single paragraph without breaking true breaks.",
                icon: .system("text.line.2.summary"),
                hasSubActions: false,
                hasParameters: false
            ),
            ActionMetadata(
                id: "search_web",
                title: "Search Web",
                description: "Directly open detected web links or search selected text online.",
                icon: .system("magnifyingglass"),
                hasSubActions: false,
                hasParameters: true
            )
        ]
        if #available(macOS 15.0, *) {
            actions.append(
                ActionMetadata(
                    id: "translate",
                    title: "Translate",
                    description: "Private neural translation powered by Apple Translation.",
                    icon: .system("globe"),
                    hasSubActions: true,
                    hasParameters: true
                )
            )
        }
        return actions
    }
    
    static let caseSubActionsMetadata: [ActionMetadata] = [
        ActionMetadata(id: "title_case", title: "Title Case", description: "Capitalize every principal word", icon: .typography("Aa"), hasSubActions: false, hasParameters: false),
        ActionMetadata(id: "uppercase", title: "UPPERCASE", description: "Convert all characters to uppercase", icon: .typography("AA"), hasSubActions: false, hasParameters: false),
        ActionMetadata(id: "lowercase", title: "lowercase", description: "Convert all characters to lowercase", icon: .typography("aa"), hasSubActions: false, hasParameters: false),
        ActionMetadata(id: "toggle_case", title: "tOGGLE cASE", description: "Invert uppercase and lowercase characters", icon: .typography("aA"), hasSubActions: false, hasParameters: false),
        ActionMetadata(id: "sentence_case", title: "Sentence case.", description: "Capitalize only the first letter of sentences", icon: .system("text.alignleft"), hasSubActions: false, hasParameters: false)
    ]
    
    static var translateSubActionsMetadata: [ActionMetadata] {
        TranslationTargetLanguage.supportedLanguages.map { lang in
            ActionMetadata(
                id: "translate_to_\(lang.code)",
                title: lang.name,
                description: "Translate to \(lang.name)",
                icon: .system("globe"),
                hasSubActions: false,
                hasParameters: false
            )
        }
    }
}

// MARK: - Web Action & URL Detection Helper

/// Pure URL detection and browser navigation helper for Quick Actions.
enum WebActionHelper {
    
    /// Detects if the given text matches a valid URL pattern.
    static func detectURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Reject text containing whitespace or newlines internally
        if trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return nil
        }
        
        // Explicit http:// or https:// scheme
        if trimmed.range(of: #"^https?://\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return URL(string: trimmed)
        }
        
        // Standard domain or sub-domain pattern without scheme (e.g. github.com, apple.com/macos)
        let domainRegex = #"^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(:\d+)?(/.*)?$"#
        if trimmed.range(of: domainRegex, options: .regularExpression) != nil {
            return URL(string: "https://" + trimmed)
        }
        
        // Fallback validation via NSDataDetector
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count))
            if matches.count == 1, let match = matches.first, match.range.location == 0, match.range.length == trimmed.utf16.count, let url = match.url {
                return url
            }
        }
        
        return nil
    }
    
    /// Returns true if the text matches a valid URL pattern.
    static func isURL(_ text: String) -> Bool {
        detectURL(in: text) != nil
    }
    
    /// Generates a Search URL with percent-encoded query for the specified search engine.
    static func searchURL(for query: String, engine: SearchEngine = .google) -> URL? {
        engine.searchURL(for: query)
    }
    
    /// Executes the open URL or web search action in the user's default browser.
    @discardableResult
    static func execute(for text: String, engine: SearchEngine = .google) -> Bool {
        if let url = detectURL(in: text) {
            return NSWorkspace.shared.open(url)
        } else if let searchURL = engine.searchURL(for: text) {
            return NSWorkspace.shared.open(searchURL)
        }
        return false
    }
}

// MARK: - DRY Transformation Functions

/// Pure text transformation functions for Quick Actions, designed for DRY reuse and isolated testing.
enum QuickActionTransforms {
    
    /// Unwraps single newlines within paragraphs into spaces while preserving true double-newline paragraph breaks.
    /// Automatically trims leading/trailing whitespace per line to avoid double spaces.
    static func joinLines(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        
        return normalized.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .joined(separator: "\n\n")
    }
    
    /// Converts text to Title Case.
    static func toTitleCase(_ text: String) -> String {
        text.capitalized
    }
    
    /// Converts text to UPPERCASE.
    static func toUppercase(_ text: String) -> String {
        text.uppercased()
    }
    
    /// Converts text to lowercase.
    static func toLowercase(_ text: String) -> String {
        text.lowercased()
    }
    
    /// Converts text to Sentence case (capitalizing first letter of each sentence).
    static func toSentenceCase(_ text: String) -> String {
        let sentences = text.components(separatedBy: ". ")
        return sentences.map { sentence in
            guard let first = sentence.first else { return sentence }
            return String(first).uppercased() + sentence.dropFirst().lowercased()
        }.joined(separator: ". ")
    }
    
    /// Inverts character cases (uppercase -> lowercase, lowercase -> uppercase).
    static func toToggleCase(_ text: String) -> String {
        String(text.map { char in
            char.isUppercase ? (char.lowercased().first ?? char) : (char.uppercased().first ?? char)
        })
    }
}
