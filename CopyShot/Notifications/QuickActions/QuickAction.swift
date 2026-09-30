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
    var shortcutNumber: Int?
    let transform: (String) -> String
    let subActions: [QuickAction]?
    let targetLanguageCode: String?
    let operation: ActionOperation
    let helpText: String?
    
    var hasSubmenu: Bool {
        guard let subActions = subActions else { return false }
        return !subActions.isEmpty
    }
    
    init(
        id: String,
        title: String,
        icon: ActionIcon,
        shortcutNumber: Int?,
        transform: @escaping (String) -> String = { $0 },
        subActions: [QuickAction]? = nil,
        targetLanguageCode: String? = nil,
        operation: ActionOperation? = nil,
        helpText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutNumber = shortcutNumber
        self.transform = transform
        self.subActions = subActions
        self.targetLanguageCode = targetLanguageCode
        self.operation = operation ?? targetLanguageCode.map(ActionOperation.translate) ?? .transform
        self.helpText = helpText
    }
    
    static func == (lhs: QuickAction, rhs: QuickAction) -> Bool {
        lhs.operation == rhs.operation &&
        lhs.helpText == rhs.helpText &&
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
        defaultActions(for: nil, mode: .standardOCR)
    }
    
    /// Returns default quick actions dynamically adjusted for the recognized text using default configuration.
    static func defaultActions(for text: String?, mode: CaptureMode = .standardOCR) -> [QuickAction] {
        actions(for: text, mode: mode, config: QuickActionsConfig())
    }
    
    /// Constructs ordered, active quick actions based on user configuration, recognized capture text, and capture mode.
    static func actions(for text: String?, mode: CaptureMode = .standardOCR, config: QuickActionsConfig) -> [QuickAction] {
        guard config.isEnabled else { return [] }
        
        return ActionRegistry.shared.actions(context: ActionContext(text: text ?? "", mode: mode), config: config)
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
        let baseURL: String
        switch self {
        case .google:
            baseURL = "https://www.google.com/search"
        case .duckDuckGo:
            baseURL = "https://duckduckgo.com/"
        case .bing:
            baseURL = "https://www.bing.com/search"
        case .kagi:
            baseURL = "https://kagi.com/search"
        case .brave:
            baseURL = "https://search.brave.com/search"
        case .ecosia:
            baseURL = "https://www.ecosia.org/search"
        }
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
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

// MARK: - Action Metadata Registry

/// Declarative metadata for built-in Quick Actions, utilized by the Settings configuration interface.
struct ActionMetadata: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let icon: ActionIcon
    let hasSubActions: Bool
    let hasParameters: Bool
    
    var supportedModes: Set<CaptureMode> = [.standardOCR]
    var parameters: [ActionParameter] = []

    static var allActions: [ActionMetadata] {
        ActionRegistry.shared.definitions.map(\.metadata)
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
    
    /// Wraps LaTeX math formula in $...$ (or cycles to $$...$$, then back to raw unwrapped formula).
    static func wrapDollar(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count >= 4 {
            let inner = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespacesAndNewlines)
            return String(inner)
        } else if trimmed.hasPrefix("$") && trimmed.hasSuffix("$") && trimmed.count >= 2 {
            let inner = trimmed.dropFirst(1).dropLast(1).trimmingCharacters(in: .whitespacesAndNewlines)
            return "$$\(inner)$$"
        } else {
            return "$\(trimmed)$"
        }
    }
}
