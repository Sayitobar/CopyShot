import Combine
import XCTest
@testable import CopyShot

@MainActor
final class CustomActionLibraryTests: XCTestCase {
    func testManagementSortsTitlesWithoutChangingShelfOrder() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(defaults: defaults)
        for title in ["Zulu", "alpha", "Beta"] {
            try library.saveURLAction(.init(title: title, template: "https://example.com/?q={text}"))
        }
        XCTAssertEqual(library.catalog.managementActions.map { $0.metadata.title }, ["alpha", "Beta", "Zulu"])
        XCTAssertEqual(library.catalog.actions.map { $0.metadata.title }, ["Zulu", "alpha", "Beta"])
    }

    func testScriptRemovalRefreshesBothCatalogsAndCanBeRestored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("one.sh")
        try writeScript("#!/bin/sh\n# @copyshot.id removable\ncat", to: file)
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(directory: directory, defaults: defaults)
        await library.reload()
        guard case .script(let script) = library.catalog.actions.first else { return XCTFail("Missing fixture script") }
        var config = QuickActionsConfig()
        var scoped = config.modeConfiguration(for: .standardOCR, registry: library.catalog.registry)
        scoped.disabledActionIds.removeAll { $0 == script.metadata.id }
        config.setModeConfiguration(scoped, for: .standardOCR, registry: library.catalog.registry)
        let saved = directory.appendingPathComponent("restorable.txt")
        try await library.deleteScript(script) { script in try FileManager.default.moveItem(at: script.fileURL, to: saved) }
        XCTAssertTrue(library.catalog.managementActions.isEmpty)
        XCTAssertFalse(library.catalog.registry.actions(context: .init(text: "Text", mode: .standardOCR), config: config).contains { $0.id == script.metadata.id })
        try FileManager.default.moveItem(at: saved, to: file)
        await library.reload()
        XCTAssertTrue(library.catalog.registry.actions(context: .init(text: "Text", mode: .standardOCR), config: config).contains { $0.id == script.metadata.id })
    }

    func testFailedScriptRemovalKeepsTheActionAvailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("one.sh")
        try writeScript("#!/bin/sh\ncat", to: file)
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(directory: directory, defaults: defaults)
        await library.reload()
        guard case .script(let script) = library.catalog.actions.first else { return XCTFail("Missing fixture script") }
        do {
            try await library.deleteScript(script) { _ in throw CocoaError(.fileWriteNoPermission) }
            XCTFail("Removal should fail")
        } catch {}
        XCTAssertEqual(library.catalog.managementActions, [.script(script)])
        XCTAssertEqual(library.catalog.actions, [.script(script)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testScriptChangedSinceConfirmationIsNotRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("one.sh")
        try writeScript("#!/bin/sh\ncat", to: file)
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(directory: directory, defaults: defaults)
        await library.reload()
        guard case .script(let script) = library.catalog.actions.first else { return XCTFail("Missing fixture script") }
        try writeScript("#!/bin/sh\n# Edited while the removal prompt was open\ncat", to: file)
        var attemptedRemoval = false
        do {
            try await library.deleteScript(script) { _ in attemptedRemoval = true }
            XCTFail("A changed script needs a fresh confirmation")
        } catch CustomActionError.scriptChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(attemptedRemoval)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPublishedActionsCanBeResolvedImmediately() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(defaults: defaults)
        let link = CustomURLAction(title: "Link", template: "https://example.com/?q={text}")
        var config = QuickActionsConfig()
        config.setModeConfiguration(.init(actionOrder: [link.actionID], disabledActionIds: []), for: .standardOCR)
        var deliveries = 0
        let subscription = library.$catalog.dropFirst().sink { catalog in
            deliveries += 1
            let actions = catalog.registry.actions(context: .init(text: "Captured", mode: .standardOCR), config: config)
            XCTAssertEqual(actions.map(\.id), [link.actionID])
        }
        try library.saveURLAction(link)
        XCTAssertEqual(deliveries, 1)
        withExtendedLifetime(subscription) {}
    }

    func testUnavailableSavedURLRemainsManageableForRepairOrDeletion() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = CustomActionLibrary(defaults: defaults, hasHandler: { _ in true })
        var link = CustomURLAction(title: "Uninstalled App", template: "fixtureapp://new?text={text}")
        try original.saveURLAction(link)
        let unavailable = CustomActionLibrary(defaults: defaults, hasHandler: { _ in false })
        XCTAssertTrue(unavailable.catalog.actions.isEmpty)
        XCTAssertEqual(unavailable.catalog.managementActions, [.url(link)])
        XCTAssertFalse(unavailable.catalog.diagnostics.isEmpty)
        link.template = "https://example.com/?q={text}"
        try unavailable.saveURLAction(link)
        XCTAssertEqual(unavailable.catalog.actions, [.url(link)])
        unavailable.deleteURLAction(id: link.id)
        XCTAssertTrue(unavailable.catalog.managementActions.isEmpty)
        XCTAssertTrue(CustomActionLibrary(defaults: defaults).urlActions.isEmpty)
    }

    func testURLPersistenceAndResetKeepAuthoredDefinitions() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(defaults: defaults, hasHandler: { _ in true })
        let link = CustomURLAction(title: "Open", supportedModes: [.standardOCR, .table], template: "https://example.com/?q={text}")
        try library.saveURLAction(link)
        let reloaded = CustomActionLibrary(defaults: defaults, hasHandler: { _ in true })
        XCTAssertEqual(reloaded.urlActions, [link])
        var config = QuickActionsConfig()
        let catalog = reloaded.catalog.registry.catalog(for: .table, config: config)
        XCTAssertEqual(catalog.last?.metadata.id, link.actionID)
        XCTAssertFalse(try XCTUnwrap(catalog.last).isEnabled)
        var table = config.modeConfiguration(for: .table, registry: library.catalog.registry)
        table.disabledActionIds.removeAll { $0 == link.actionID }
        config.setModeConfiguration(table, for: .table, registry: library.catalog.registry)
        XCTAssertTrue(library.catalog.registry.catalog(for: .table, config: config).last?.isEnabled == true)
        XCTAssertFalse(library.catalog.registry.catalog(for: .standardOCR, config: config).last?.isEnabled ?? true)
        config = QuickActionsConfig()
        XCTAssertEqual(library.urlActions, [link])
        XCTAssertFalse(library.catalog.registry.catalog(for: .table, config: config).last?.isEnabled ?? true)
        reloaded.deleteURLAction(id: link.id)
        XCTAssertTrue(CustomActionLibrary(defaults: defaults).urlActions.isEmpty)
    }

    func testReloadPreservesScriptPreferencesThroughRemovalAndRename() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("one.sh")
        try writeScript("#!/bin/sh\n# @copyshot.id stable\ncat", to: file)
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(directory: directory, defaults: defaults)
        await library.reload()
        let id = try XCTUnwrap(library.catalog.actions.first).metadata.id
        var config = QuickActionsConfig()
        var scoped = config.modeConfiguration(for: .standardOCR, registry: library.catalog.registry)
        scoped.disabledActionIds.removeAll { $0 == id }
        config.setModeConfiguration(scoped, for: .standardOCR, registry: library.catalog.registry)
        try FileManager.default.removeItem(at: file)
        await library.reload()
        XCTAssertTrue(config.modeConfiguration(for: .standardOCR, registry: library.catalog.registry).actionOrder.contains(id))
        try writeScript("#!/bin/sh\n# @copyshot.id stable\ncat", to: directory.appendingPathComponent("renamed.sh"))
        await library.reload()
        XCTAssertTrue(library.catalog.registry.catalog(for: .standardOCR, config: config).last?.isEnabled ?? false)
    }

    func testWatcherSeesInPlaceEditsAtomicReplacementAndNewFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = directory.appendingPathComponent("test.sh")
        try writeScript("#!/bin/sh\n# @copyshot.title Original\ncat", to: file)
        let library = CustomActionLibrary(directory: directory, defaults: defaults)
        library.start()
        defer { library.stop() }
        try await waitUntil { library.catalog.actions.count == 1 }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("#!/bin/sh\n# @copyshot.title Edited\ncat".utf8))
        try handle.close()
        try await waitUntil { library.catalog.actions.first?.metadata.title == "Edited" }
        try writeScript("#!/bin/sh\n# @copyshot.title Replaced\ncat", to: file)
        try await waitUntil { library.catalog.actions.first?.metadata.title == "Replaced" }
        try writeScript("#!/bin/sh\ncat", to: directory.appendingPathComponent("new.sh"))
        try await waitUntil { library.catalog.actions.count == 2 }
        try FileManager.default.removeItem(at: file)
        try await waitUntil { library.catalog.actions.count == 1 }
    }

    func testInvalidURLDoesNotReplaceSavedDefinition() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(defaults: defaults)
        var link = CustomURLAction(title: "Link", template: "https://example.com/?q={text}")
        try library.saveURLAction(link)
        link.template = "file:///{text}"
        XCTAssertThrowsError(try library.saveURLAction(link))
        XCTAssertEqual(library.urlActions.first?.template, "https://example.com/?q={text}")
    }

    func testStoppingLibraryCancelsWatchingAndReleasesItsObservers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = directory.appendingPathComponent("test.sh")
        try writeScript("#!/bin/sh\ncat", to: file)
        var library: CustomActionLibrary? = CustomActionLibrary(directory: directory, defaults: defaults)
        weak var lifetime = library
        library?.start()
        try await waitUntil { library?.catalog.actions.count == 1 }
        library?.stop()
        let actions = library?.catalog.actions
        try writeScript("#!/bin/sh\n# @copyshot.title Edited\ncat", to: file)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(library?.catalog.actions, actions)
        library = nil
        XCTAssertNil(lifetime)
    }

    private func writeScript(_ source: String, to url: URL) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(predicate())
    }
}
