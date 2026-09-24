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
    
    @Test("ClipboardManager copies string to system pasteboard")
    func testCopyToClipboard() {
        let testToken = "CopyShot-Test-Token-\(UUID().uuidString)"
        
        ClipboardManager.copyToClipboard(text: testToken)
        
        let pasteboard = NSPasteboard.general
        let readBack = pasteboard.string(forType: .string)
        
        #expect(readBack == testToken)
    }
    
    @Test("ClipboardManager handles multiline and unicode text")
    func testUnicodeAndMultiline() {
        let unicodeText = "Line 1: ⌘ CopyShot\nLine 2: 日本語 / English / 12345\nLine 3: 🚀"
        
        ClipboardManager.copyToClipboard(text: unicodeText)
        
        let pasteboard = NSPasteboard.general
        let readBack = pasteboard.string(forType: .string)
        
        #expect(readBack == unicodeText)
    }
}
