//
//  QuickAction.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import Foundation
import SwiftUI

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
    
    // MARK: - Default Actions
    
    /// Default set of quick actions available for text captures.
    static var defaultActions: [QuickAction] {
        defaultActions(for: nil)
    }
    
    /// Returns default quick actions dynamically adjusted for the recognized text (e.g. Open URL vs Search Web).
    static func defaultActions(for text: String?) -> [QuickAction] {
        // Slot 1: Change Case with 5 flyout transforms
        let caseSubActions: [QuickAction] = [
            QuickAction(
                id: "title_case",
                title: "Title Case",
                icon: .typography("Aa"),
                shortcutNumber: 1,
                transform: QuickActionTransforms.toTitleCase
            ),
            QuickAction(
                id: "uppercase",
                title: "UPPERCASE",
                icon: .typography("AA"),
                shortcutNumber: 2,
                transform: QuickActionTransforms.toUppercase
            ),
            QuickAction(
                id: "lowercase",
                title: "lowercase",
                icon: .typography("aa"),
                shortcutNumber: 3,
                transform: QuickActionTransforms.toLowercase
            ),
            QuickAction(
                id: "toggle_case",
                title: "tOGGLE cASE",
                icon: .typography("aA"),
                shortcutNumber: 4,
                transform: QuickActionTransforms.toToggleCase
            ),
            QuickAction(
                id: "sentence_case",
                title: "Sentence case.",
                icon: .system("text.alignleft"),
                shortcutNumber: 5,
                transform: QuickActionTransforms.toSentenceCase
            )
        ]
        
        let changeCase = QuickAction(
            id: "change_case",
            title: "Change Case",
            icon: .system("textformat"),
            shortcutNumber: 1,
            transform: QuickActionTransforms.toTitleCase,
            subActions: caseSubActions
        )
        
        // Slot 2: Join Lines
        let joinLines = QuickAction(
            id: "join_lines",
            title: "Join Lines",
            icon: .system("text.line.2.summary"),
            shortcutNumber: 2,
            transform: QuickActionTransforms.joinLines
        )
        
        // Slot 3: Search Web / Open URL (Dynamic based on capture content)
        let isURL = text != nil && WebActionHelper.isURL(text!)
        let webAction = QuickAction(
            id: "search_web",
            title: isURL ? "Open URL" : "Search Web",
            icon: isURL ? .system("safari") : .system("magnifyingglass"),
            shortcutNumber: 3,
            transform: { $0 }
        )
        
        var actions: [QuickAction] = [changeCase, joinLines, webAction]
        
        // Slot 4: Translate (Strictly gated to macOS 15.0+ Sequoia)
        if #available(macOS 15.0, *) {
            let translationSubActions: [QuickAction] = [
                QuickAction(
                    id: "translate_to_es",
                    title: "Spanish (es)",
                    icon: .system("globe"),
                    shortcutNumber: 1,
                    transform: { $0 },
                    targetLanguageCode: "es"
                ),
                QuickAction(
                    id: "translate_to_de",
                    title: "German (de)",
                    icon: .system("globe"),
                    shortcutNumber: 2,
                    transform: { $0 },
                    targetLanguageCode: "de"
                ),
                QuickAction(
                    id: "translate_to_fr",
                    title: "French (fr)",
                    icon: .system("globe"),
                    shortcutNumber: 3,
                    transform: { $0 },
                    targetLanguageCode: "fr"
                ),
                QuickAction(
                    id: "translate_to_ja",
                    title: "Japanese (ja)",
                    icon: .system("globe"),
                    shortcutNumber: 4,
                    transform: { $0 },
                    targetLanguageCode: "ja"
                ),
                QuickAction(
                    id: "translate_to_zh",
                    title: "Chinese (zh)",
                    icon: .system("globe"),
                    shortcutNumber: 5,
                    transform: { $0 },
                    targetLanguageCode: "zh"
                )
            ]
            
            let translate = QuickAction(
                id: "translate",
                title: "Translate (to en.)",
                icon: .system("translate"),
                shortcutNumber: 4,
                transform: { $0 },
                subActions: translationSubActions,
                targetLanguageCode: "en"
            )
            actions.append(translate)
        }
        
        return actions
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
    
    /// Generates a Google Search URL with percent-encoded query.
    static func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return nil
        }
        return url
    }
    
    /// Executes the open URL or web search action in the user's default browser.
    @discardableResult
    static func execute(for text: String) -> Bool {
        if let url = detectURL(in: text) {
            return NSWorkspace.shared.open(url)
        } else if let searchURL = searchURL(for: text) {
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
