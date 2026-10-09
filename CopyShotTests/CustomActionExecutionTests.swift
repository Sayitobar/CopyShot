import XCTest
@testable import CopyShot

/// The production backend is NSUserUnixTask. Tests inject a sandbox-inheriting Process
/// so fixtures stay in private temporary directories rather than installing user scripts.
private final class FixtureScriptTask: ScriptTask {
    var standardInput: FileHandle?
    var standardOutput: FileHandle?
    var standardError: FileHandle?
    let url: URL
    let process = Process()
    init(url: URL) { self.url = url }
    func launch(completion: @escaping @Sendable (Error?) -> Void) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { process in
            completion(process.terminationStatus == 0 ? nil : NSError(domain: "FixtureScript", code: Int(process.terminationStatus)))
        }
        try process.run()
    }
}

@MainActor
final class CustomActionExecutionTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func script(_ body: String, headers: String = "") throws -> ScriptAction {
        let url = directory.appendingPathComponent("\(UUID().uuidString).sh")
        let source = "#!/bin/sh\n\(headers)\n\(body)"
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return try ScriptAction.parse(source: source, url: url)
    }

    private func runner() -> UserScriptRunner { UserScriptRunner(makeTask: { FixtureScriptTask(url: $0) }) }

    func testConcurrentStreamsAndInputBeyondPipeCapacityAreLossless() async throws {
        let action = try script("/usr/bin/head -c 200000 /dev/zero >&2\n/bin/cat")
        let input = String(repeating: "ä $(touch forbidden) `echo no` &\n", count: 10000)
        let result = try await runner().run(action, input: input)
        XCTAssertEqual(result, input)
    }

    func testCopyPreservesEmptyAndTrailingNewlinesAndCanonicalPayload() async throws {
        let context = ActionContext(payload: .table(.init(rows: [["A", "B"], ["1", "2"]])))
        let executor = ActionExecutor(scriptRunner: runner())
        for (body, expected) in [("/bin/cat >/dev/null", ""), ("/bin/cat >/dev/null; /usr/bin/printf 'result\\n\\n'", "result\n\n")] {
            let tableScript = try script(body, headers: "# @copyshot.modes table")
            let tableAction = QuickAction(id: tableScript.metadata.id, title: "Script", icon: .system("terminal"), shortcutNumber: nil, operation: .custom(.script(tableScript)))
            guard case .copy(let updated, _) = try await executor.execute(tableAction, context: context, config: .init()) else { return XCTFail("Expected copy") }
            XCTAssertEqual(updated.text, expected)
            XCTAssertEqual(updated.payload, context.payload)
        }
    }

    func testCompletionAndURLResultsHaveNoClipboardEffects() async throws {
        let executor = ActionExecutor(scriptRunner: runner(), hasHandler: { _ in true })
        let context = ActionContext(payload: .standardText("a & b"))
        let completion = try script("/bin/cat >/dev/null; /usr/bin/printf 'ignored'", headers: "# @copyshot.output none")
        let action = QuickAction(id: completion.metadata.id, title: "Side effect", icon: .system("terminal"), shortcutNumber: nil, operation: .custom(.script(completion)))
        guard case .completed = try await executor.execute(action, context: context, config: .init()) else { return XCTFail("Expected completion") }
        let link = CustomURLAction(title: "Link", template: "https://example.com/?q={text}")
        let urlAction = QuickAction(id: link.actionID, title: link.title, icon: .system("link"), shortcutNumber: nil, operation: .custom(.url(link)))
        guard case .openURL(let url) = try await executor.execute(urlAction, context: context, config: .init()) else { return XCTFail("Expected URL") }
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, context.text)
        let urlScript = try script("/bin/cat >/dev/null; /usr/bin/printf 'https://example.com/path\\n'", headers: "# @copyshot.output open-url")
        guard case .openURL(let scriptURL) = try await executor.execute(QuickAction(id: "url", title: "URL", icon: .system("link"), shortcutNumber: nil, operation: .custom(.script(urlScript))), context: context, config: .init()) else { return XCTFail("Expected URL") }
        XCTAssertEqual(scriptURL.absoluteString, "https://example.com/path")
    }

    func testNonzeroExitAndInvalidUTF8AndOutputLimitsFail() async throws {
        let backend = runner()
        let failure = try script("/bin/cat >/dev/null; /usr/bin/printf 'useful error' >&2; exit 7")
        do { _ = try await backend.run(failure, input: "x"); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("useful error")) }
        for body in ["/bin/cat >/dev/null; /usr/bin/printf '\\377'", "/bin/cat >/dev/null; /usr/bin/head -c 4194305 /dev/zero"] {
            do { _ = try await backend.run(try script(body), input: "x"); XCTFail("Expected failure") } catch {}
        }
        do { _ = try await backend.run(try script("/bin/cat"), input: String(repeating: "x", count: 4194305)); XCTFail("Expected input limit") } catch {}
    }

    func testTimeoutRetainsSlotUntilOSCompletionAndRejectsDuplicateRun() async throws {
        let backend = runner()
        let slow = try script("/bin/sleep 0.6", headers: "# @copyshot.timeout 0.05")
        do { _ = try await backend.run(slow, input: "x"); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Stopped waiting")) }
        XCTAssertEqual(backend.activeInvocationCount, 1)
        do { _ = try await backend.run(slow, input: "x"); XCTFail("Expected busy") }
        catch { XCTAssertTrue(error.localizedDescription.contains("still running")) }
        try await waitUntil { backend.activeInvocationCount == 0 }
    }

    func testFourAbandonedInvocationsKeepTheGlobalLimitUntilCompletion() async throws {
        let backend = runner()
        let actions = try (0..<4).map { _ in try script("/bin/sleep 1", headers: "# @copyshot.timeout 0.05") }
        let executions = actions.map { action in Task { try await backend.run(action, input: "") } }
        for execution in executions {
            do { _ = try await execution.value; XCTFail("Expected timeout") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Stopped waiting")) }
        }
        XCTAssertEqual(backend.activeInvocationCount, 4)
        do { _ = try await backend.run(try script("/bin/cat"), input: ""); XCTFail("Expected global limit") }
        catch { XCTAssertTrue(error.localizedDescription.contains("four script runs")) }
        try await waitUntil { backend.activeInvocationCount == 0 }
        let available = try await backend.run(try script("/bin/cat"), input: "available")
        XCTAssertEqual(available, "available")
    }

    func testCancellationReturnsBeforeScriptFinishesAndChangedScriptsCannotLaunch() async throws {
        let backend = runner()
        let slow = try script("/bin/sleep 0.5")
        let execution = Task { try await backend.run(slow, input: "x") }
        try await Task.sleep(for: .milliseconds(80))
        execution.cancel()
        do { _ = try await execution.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(backend.activeInvocationCount, 1)
        try await waitUntil { backend.activeInvocationCount == 0 }
        try "#!/bin/sh\nexit 0".write(to: slow.fileURL, atomically: true, encoding: .utf8)
        do { _ = try await backend.run(slow, input: "x"); XCTFail("Expected changed script") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
    }

    func testCancellationBeforeStartDoesNotLaunchOrOccupyASlot() async throws {
        var launched = false
        let backend = UserScriptRunner(makeTask: { launched = true; return FixtureScriptTask(url: $0) })
        let action = try script("/bin/cat")
        let execution = Task { try await backend.run(action, input: "text") }
        execution.cancel()
        do { _ = try await execution.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(launched)
        XCTAssertEqual(backend.activeInvocationCount, 0)
    }

    func testCancelledInvocationCannotReleaseAReplacementRun() async throws {
        let backend = runner()
        let action = try script("/bin/sleep 0.2; /bin/cat")
        let abandoned = Task { try await backend.run(action, input: "abandoned") }
        try await waitUntil { backend.activeInvocationCount == 1 }
        abandoned.cancel()
        do { _ = try await abandoned.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await waitUntil { backend.activeInvocationCount == 0 }
        let replacement = Task { try await backend.run(action, input: "replacement") }
        try await waitUntil { backend.activeInvocationCount == 1 }
        abandoned.cancel()
        do { _ = try await backend.run(action, input: "duplicate"); XCTFail("Expected busy") }
        catch { XCTAssertTrue(error.localizedDescription.contains("still running")) }
        let output = try await replacement.value
        XCTAssertEqual(output, "replacement")
        try await waitUntil { backend.activeInvocationCount == 0 }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate())
    }
}
