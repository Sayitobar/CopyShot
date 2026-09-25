//
//  QuickAction.swift
//  CopyShot
//
//  Created by Mac on 25.09.26.
//

import Foundation
import SwiftUI

/// Represents a single quick action executable on recognized capture text.
struct QuickAction: Identifiable, Equatable {
    let id: String
    let title: String
    let iconName: String
    let shortcutNumber: Int
    let transform: (String) -> String
    
    static func == (lhs: QuickAction, rhs: QuickAction) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - POC Sample Actions
    
    /// Default set of quick actions available for text captures.
    static let defaultActions: [QuickAction] = [
        QuickAction(
            id: "pdf_strip",
            title: "Strip Line-breaks (PDF)",
            iconName: "arrow.right.to.line",
            shortcutNumber: 1
        ) { text in
            // Unwraps single newlines within paragraphs while preserving double-newlines for paragraphs.
            text.replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n\n")
                .map { paragraph in
                    paragraph.replacingOccurrences(of: "\n", with: " ")
                             .replacingOccurrences(of: "  ", with: " ")
                }
                .joined(separator: "\n\n")
        },
        QuickAction(
            id: "title_case",
            title: "Title Case",
            iconName: "textformat",
            shortcutNumber: 2
        ) { text in
            text.capitalized
        },
        QuickAction(
            id: "uppercase",
            title: "UPPERCASE",
            iconName: "textformat.size.larger",
            shortcutNumber: 3
        ) { text in
            text.uppercased()
        },
        QuickAction(
            id: "lowercase",
            title: "lowercase",
            iconName: "textformat.size.smaller",
            shortcutNumber: 4
        ) { text in
            text.lowercased()
        },
        QuickAction(
            id: "sentence_case",
            title: "Sentence case",
            iconName: "text.alignleft",
            shortcutNumber: 5
        ) { text in
            let sentences = text.components(separatedBy: ". ")
            return sentences.map { sentence in
                guard let first = sentence.first else { return sentence }
                return String(first).uppercased() + sentence.dropFirst().lowercased()
            }.joined(separator: ". ")
        },
        QuickAction(
            id: "toggle_case",
            title: "tOGGLE cASE",
            iconName: "arrow.triangle.swap",
            shortcutNumber: 6
        ) { text in
            String(text.map { char in
                char.isUppercase ? char.lowercased().first ?? char : char.uppercased().first ?? char
            })
        },
        QuickAction(
            id: "qr_code",
            title: "QR Code Detection",
            iconName: "qrcode",
            shortcutNumber: 7
        ) { _ in
            // POC Stub: Future expansion runs Vision barcode detection on CGImage
            "https://copyshot.app/sample-qr-detected"
        },
        QuickAction(
            id: "latex",
            title: "LaTeX Math Mode",
            iconName: "function",
            shortcutNumber: 8
        ) { text in
            // POC Stub: Wraps in math delimiter
            "$$\n\(text)\n$$"
        }
    ]
}
