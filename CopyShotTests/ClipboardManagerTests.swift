//
//  ClipboardManagerTests.swift
//  CopyShotTests
//
//  Created for CopyShot.
//

import Testing
import AppKit
@testable import CopyShot

@Suite("ClipboardManager Tests", .serialized)
@MainActor
struct ClipboardManagerTests {
    
    @Test("ClipboardManager writes text to the supplied pasteboard")
    func testCopyToClipboard() {
        let testToken = "CopyShot-Test-Token-\(UUID().uuidString)"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        ClipboardManager.copyToClipboard(text: testToken, pasteboard: pasteboard)
        let readBack = pasteboard.string(forType: .string)
        
        #expect(readBack == testToken)
    }
    
    @Test("ClipboardManager handles multiline and unicode text")
    func testUnicodeAndMultiline() {
        let unicodeText = "Line 1: ⌘ CopyShot\nLine 2: 日本語 / English / 12345\nLine 3: 🚀"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        ClipboardManager.copyToClipboard(text: unicodeText, pasteboard: pasteboard)
        let readBack = pasteboard.string(forType: .string)
        
        #expect(readBack == unicodeText)
    }
}
