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
    
    init(
        id: String,
        title: String,
        icon: ActionIcon,
        shortcutNumber: Int,
        transform: @escaping (String) -> String
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutNumber = shortcutNumber
        self.transform = transform
    }
    
    static func == (lhs: QuickAction, rhs: QuickAction) -> Bool {
        lhs.id == rhs.id && lhs.shortcutNumber == rhs.shortcutNumber && lhs.icon == rhs.icon
    }
    
    // MARK: - Default Actions
    
    /// Default set of quick actions available for text captures.
    static let defaultActions: [QuickAction] = [
        QuickAction(
            id: "join_lines",
            title: "Join Lines",
            icon: .system("text.line.2.summary"),
            shortcutNumber: 1,
            transform: QuickActionTransforms.joinLines
        ),
        QuickAction(
            id: "title_case",
            title: "Title Case",
            icon: .typography("Aa"),
            shortcutNumber: 2,
            transform: QuickActionTransforms.toTitleCase
        ),
        QuickAction(
            id: "uppercase",
            title: "UPPERCASE",
            icon: .typography("AA"),
            shortcutNumber: 3,
            transform: QuickActionTransforms.toUppercase
        ),
        QuickAction(
            id: "lowercase",
            title: "lowercase",
            icon: .typography("aa"),
            shortcutNumber: 4,
            transform: QuickActionTransforms.toLowercase
        ),
        QuickAction(
            id: "toggle_case",
            title: "tOGGLE cASE",
            icon: .typography("aA"),
            shortcutNumber: 5,
            transform: QuickActionTransforms.toToggleCase
        ),
        QuickAction(
            id: "sentence_case",
            title: "Sentence case.",
            icon: .system("text.alignleft"),
            shortcutNumber: 6,
            transform: QuickActionTransforms.toSentenceCase
        )
    ]
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
