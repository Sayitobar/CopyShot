import Testing
@testable import CopyShot

@Suite("Text preview formatting")
struct CopyShotTests {
    @Test("A positive limit truncates the production preview")
    func truncatesLongText() {
        #expect(TextPreview.format("CopyShot recognized text", limit: 8) == "CopyShot...")
        #expect(TextPreview.format("short", limit: 8) == "short")
    }

    @Test("Zero means unlimited, including composed Unicode characters")
    func zeroLimitPreservesFullText() {
        let text = "A👩‍💻B\n日本語"
        #expect(TextPreview.format(text, limit: 0) == text)
        #expect(TextPreview.format(text, limit: 2) == "A👩‍💻...")
    }
}
