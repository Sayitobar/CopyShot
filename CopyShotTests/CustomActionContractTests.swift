import XCTest
@testable import CopyShot

final class CustomActionContractTests: XCTestCase {
    func testStarterScriptsAreBundledAndExecutable() throws {
        for name in ["strip_line_numbers", "remove_blank_lines"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "sh", subdirectory: "StarterActions")
                                    ?? Bundle.main.url(forResource: name, withExtension: "sh"))
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
            let parsed = try ScriptAction.parse(source: String(contentsOf: url, encoding: .utf8), url: url)
            XCTAssertTrue(parsed.metadata.id.hasPrefix("custom.script.copyshot."))
        }
    }
    func testPlainScriptDefaultsAndHeadersStopAtFirstCommand() throws {
        let url = URL(fileURLWithPath: "/tmp/strip_line_numbers.sh")
        let script = try ScriptAction.parse(source: "#!/bin/sh\ncat\n# @copyshot.output none\n", url: url)
        XCTAssertEqual(script.metadata.id, "custom.script.strip_line_numbers.sh")
        XCTAssertEqual(script.metadata.title, "strip line numbers")
        XCTAssertEqual(script.metadata.supportedModes, [.standardOCR])
        XCTAssertEqual(script.output, .copy)
        XCTAssertEqual(script.timeout, 30)
    }

    func testExplicitMetadataAndIdentitySurviveRename() throws {
        let source = """
        #!/bin/sh
        # @copyshot.id example.stable
        # @copyshot.title Send text
        # @copyshot.description A useful script
        # @copyshot.icon link
        # @copyshot.modes standardOCR, qrBarcode, latex, table
        # @copyshot.output open-url
        # @copyshot.timeout 120
        cat
        """
        let original = try ScriptAction.parse(source: source, url: URL(fileURLWithPath: "/tmp/one.sh"))
        let renamed = try ScriptAction.parse(source: source, url: URL(fileURLWithPath: "/tmp/two.sh"))
        XCTAssertEqual(original.metadata.id, renamed.metadata.id)
        XCTAssertEqual(original.metadata.title, "Send text")
        XCTAssertEqual(original.metadata.supportedModes.count, 4)
        XCTAssertEqual(original.output, .openURL)
        XCTAssertEqual(original.timeout, 120)
    }

    func testMalformedKnownHeadersAreRejected() {
        for header in ["modes typo", "output clipboard", "timeout -1", "timeout nan", "id ", "title ", "modes ", "timeout 0"] {
            XCTAssertThrowsError(try ScriptAction.parse(source: "# @copyshot.\(header)\ncat", url: URL(fileURLWithPath: "/tmp/test.sh")))
        }
        XCTAssertThrowsError(try ScriptAction.parse(source: "# @copyshot.title One\n# @copyshot.title Two\ncat", url: URL(fileURLWithPath: "/tmp/test.sh")))
    }

    func testTemplateEncodesPayloadOnceAndDoesNotChangeDestination() throws {
        let text = "ä & a=b#c / $(echo x)\n%20"
        for token in ["{text}", "{encoded_text}"] {
            let url = try ActionURLHelper.expand("https://example.com/find?q=\(token)", text: text, hasHandler: { _ in true })
            XCTAssertEqual(url.host, "example.com")
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, text)
        }
        let app = try ActionURLHelper.expand("obsidian://new?content={text}", text: text, hasHandler: { _ in true })
        XCTAssertEqual(app.scheme, "obsidian")
        XCTAssertEqual(URLComponents(url: app, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, text)
    }

    func testTemplateAndOutputRejectUnsafeOrVariableDestinations() {
        for template in ["file:///tmp/{text}", "javascript:{text}", "data:text/plain,{text}", "https://{text}/", "{text}://example.com", "https://example.com/{unknown}", "https:///foo"] {
            XCTAssertThrowsError(try ActionURLHelper.expand(template, text: "example", hasHandler: { _ in true }), template)
        }
        XCTAssertThrowsError(try ActionURLHelper.expand("missingapp://new?text={text}", text: "x", hasHandler: { _ in false }))
        XCTAssertThrowsError(try ActionURLHelper.validate("https://example.com\nhttps://other.com", hasHandler: { _ in true }))
    }

    func testDiscoveryRejectsDuplicateIDsAndNonExecutableFilesWithoutRunningAnything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["one.sh", "two.sh"] {
            let url = directory.appendingPathComponent(name)
            try "#!/bin/sh\n# @copyshot.id duplicate\nexit 0".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try "#!/bin/sh\ncat".write(to: directory.appendingPathComponent("not_executable.sh"), atomically: true, encoding: .utf8)
        try "text".write(to: directory.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let scan = ScriptActionDiscovery.scan(directory: directory)
        XCTAssertTrue(scan.actions.isEmpty)
        XCTAssertEqual(scan.diagnostics.count, 4)
        XCTAssertTrue(scan.diagnostics.contains { $0.message.contains("chmod") })
    }
}
