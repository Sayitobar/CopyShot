import AppKit
import Combine
import XCTest
@testable import CopyShot

@MainActor
private final class ControlledCustomExecutor: ActionExecuting {
    var completion: CheckedContinuation<ActionResult, Error>?
    var count = 0
    func execute(_ action: QuickAction, context: ActionContext, config: QuickActionsConfig) async throws -> ActionResult {
        count += 1
        return try await withCheckedThrowingContinuation { completion = $0 }
    }
}

@MainActor
final class CustomActionSessionTests: XCTestCase {
    func testLibraryRefreshClosesVisibleSubmenuBeforeParentShortcutsResume() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(defaults: defaults)
        let presenter = NotificationPresenter(actionLibrary: library, configProvider: { QuickActionsConfig() },
                                             dismissScheduler: { _, _ in AnyCancellable {} })
        defer { presenter.dismissNotification() }
        presenter.showNotification(title: "Text", body: "text", accentColor: .green, supportsQuickActions: true)
        // A catalog update reopens an already-open shelf, which creates its window.
        presenter.isShelfOpen = true
        var link = CustomURLAction(title: "Link", template: "https://example.com/?q={text}")
        try library.saveURLAction(link)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let parent = try XCTUnwrap(presenter.quickActions.first { $0.id == "change_case" })
        // Hover and submenu-only activation share the same flyout presentation path.
        let menu = QuickAction(id: parent.id, title: parent.title, icon: parent.icon,
                               shortcutNumber: parent.shortcutNumber, subActions: parent.subActions, operation: .submenu)
        presenter.triggerQuickAction(menu)
        let flyout = try XCTUnwrap(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible })
        XCTAssertEqual(presenter.activeSubmenu?.id, menu.id)
        XCTAssertEqual(presenter.actionForShortcut(1)?.id, "title_case")
        link.title = "Edited"
        try library.saveURLAction(link)
        XCTAssertNil(presenter.activeSubmenu)
        XCTAssertFalse(flyout.isVisible, "Child badges must disappear when numeric keys resume parent actions.")
        XCTAssertEqual(presenter.actionForShortcut(1)?.id, "change_case")
    }

    func testRunningHUDDoesNotAutoDismissOrActivateAnotherAction() async throws {
        let executor = ControlledCustomExecutor()
        var scheduled = 0
        var copied: [String] = []
        let presenter = NotificationPresenter(actionExecutor: executor, copyText: { copied.append($0) }, animationScheduler: { $0() }, dismissScheduler: { _, _ in scheduled += 1; return AnyCancellable {} })
        let context = ActionContext(payload: .standardText("original"))
        presenter.showNotification(title: "Capture", body: "original", accentColor: .green, supportsQuickActions: true, actionContext: context)
        let previousSchedules = scheduled
        let script = try ScriptAction.parse(source: "#!/bin/sh\ncat", url: URL(fileURLWithPath: "/tmp/fixture.sh"))
        let action = QuickAction(id: script.metadata.id, title: "Fixture", icon: .system("terminal"), shortcutNumber: 1, operation: .custom(.script(script)))
        presenter.triggerQuickAction(action)
        XCTAssertTrue(presenter.isRunningAction)
        XCTAssertTrue(presenter.isShowingNotification)
        XCTAssertFalse(presenter.supportsQuickActions)
        XCTAssertNil(presenter.actionForShortcut(1))
        XCTAssertEqual(scheduled, previousSchedules)
        presenter.triggerQuickAction(action)
        for _ in 0..<30 where executor.completion == nil { await Task.yield() }
        XCTAssertEqual(executor.count, 1)
        try XCTUnwrap(executor.completion).resume(returning: .completed("Done"))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(presenter.isRunningAction)
        XCTAssertEqual(presenter.notificationBody, "Done")
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(presenter.currentActionContext, context)
        presenter.dismissNotification()
    }

    func testNewCaptureSuppressesLateScriptFailureAndClearsRunningState() async throws {
        let executor = ControlledCustomExecutor()
        let presenter = NotificationPresenter(actionExecutor: executor, animationScheduler: { $0() })
        presenter.showNotification(title: "Old", body: "old", accentColor: .green, supportsQuickActions: true)
        let script = try ScriptAction.parse(source: "#!/bin/sh\ncat", url: URL(fileURLWithPath: "/tmp/fixture.sh"))
        presenter.triggerQuickAction(QuickAction(id: script.metadata.id, title: "Fixture", icon: .system("terminal"), shortcutNumber: nil, operation: .custom(.script(script))))
        for _ in 0..<30 where executor.completion == nil { await Task.yield() }
        let continuation = try XCTUnwrap(executor.completion)
        presenter.showNotification(title: "New", body: "new", accentColor: .green)
        continuation.resume(throwing: CustomActionError.failed("late failure"))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(presenter.notificationTitle, "New")
        XCTAssertFalse(presenter.isRunningAction)
        presenter.dismissNotification()
    }

    func testLibraryChangesRefreshAnExistingCaptureAndItsShortcuts() throws {
        let suite = "CopyShotTests.custom.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = CustomActionLibrary(defaults: defaults)
        var link = CustomURLAction(title: "Original", template: "https://example.com/?q={text}")
        try library.saveURLAction(link)
        var config = QuickActionsConfig()
        config.setModeConfiguration(.init(actionOrder: [link.actionID], disabledActionIds: []), for: .standardOCR, registry: library.catalog.registry)
        let presenter = NotificationPresenter(actionLibrary: library, configProvider: { config })
        presenter.showNotification(title: "Text", body: "text", accentColor: .green, supportsQuickActions: true)
        XCTAssertEqual(presenter.quickActions.map(\.id), [link.actionID])
        XCTAssertEqual(presenter.actionForShortcut(1)?.title, "Original")
        link.title = "Edited"
        try library.saveURLAction(link)
        XCTAssertEqual(presenter.actionForShortcut(1)?.title, "Edited")
        library.deleteURLAction(id: link.id)
        XCTAssertTrue(presenter.quickActions.isEmpty)
        XCTAssertFalse(presenter.supportsQuickActions)
        try library.saveURLAction(link)
        XCTAssertTrue(presenter.supportsQuickActions)
        XCTAssertEqual(presenter.actionForShortcut(1)?.title, "Edited")
        presenter.dismissNotification()
    }
}
