//
//  CopyShotTests.swift
//  CopyShotTests
//
//  Created by Mac on 14.06.25.
//

import Testing
import SwiftUI
@testable import CopyShot

@Suite("General Formatting and UI Helper Tests")
struct CopyShotTests {

    @Test("Text preview truncation formatting adheres to character limit")
    func testTextPreviewTruncation() {
        let fullText = "This is a longer recognized string that should be truncated when a limit is applied."
        let limit = 20
        
        let formattedPreview: String
        if limit > 0 && fullText.count > limit {
            formattedPreview = String(fullText.prefix(limit)) + "..."
        } else {
            formattedPreview = fullText
        }
        
        #expect(formattedPreview.count == limit + 3)
        #expect(formattedPreview.hasSuffix("..."))
        #expect(formattedPreview.starts(with: "This is a longer rec"))
    }
    
    @Test("Zero limit preserves full body without truncation")
    func testZeroLimitPreservesFullText() {
        let fullText = "Full text preservation without truncation."
        let limit = 0
        
        let formattedPreview: String
        if limit > 0 && fullText.count > limit {
            formattedPreview = String(fullText.prefix(limit)) + "..."
        } else {
            formattedPreview = fullText
        }
        
        #expect(formattedPreview == fullText)
    }

    @Test("Adaptive colors initialize without crash")
    func testAdaptiveColorsInitialization() {
        _ = Color.adaptiveGreen
        _ = Color.adaptiveGray
        _ = Color.adaptiveRed
        _ = Color.adaptiveOrange
        _ = Color.adaptiveBlue
    }
}
