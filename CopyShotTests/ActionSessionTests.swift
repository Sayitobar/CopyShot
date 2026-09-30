import XCTest
import SwiftUI
@testable import CopyShot

@MainActor
private final class DeferredActionExecutor: ActionExecuting {
    var completion: CheckedContinuation<ActionResult, Error>?
    func execute(_ action: QuickAction, context: ActionContext, config: QuickActionsConfig) async throws -> ActionResult {
        try await withCheckedThrowingContinuation { completion = $0 }
    }
}

@MainActor
final class ActionSessionTests: XCTestCase {
    func testSubmenuDigitsNeverFallBackToParentActions() {
        let presenter = NotificationPresenter()
        presenter.quickActions = [QuickAction(id: "parent", title: "Parent", icon: .system("star"), shortcutNumber: 2)]
        let child = QuickAction(id: "child", title: "Child", icon: .system("star"), shortcutNumber: 1)
        presenter.activeSubmenu = QuickAction(id: "menu", title: "Menu", icon: .system("star"), shortcutNumber: 1, subActions: [child])
        XCTAssertEqual(presenter.actionForShortcut(1)?.id, "child")
        XCTAssertNil(presenter.actionForShortcut(2))
        XCTAssertNil(presenter.actionForShortcut(10))
    }

    func testLateExecutionCannotWriteClipboardOrReplaceNewNotification() async throws {
        let executor = DeferredActionExecutor()
        var copied: [String] = []
        let presenter = NotificationPresenter(actionExecutor: executor, copyText: { copied.append($0) }, animationScheduler: { $0() })
        let old = ActionContext(payload: .standardText("old"))
        presenter.showNotification(title: "Old", body: "preview", accentColor: .green, supportsQuickActions: true, actionContext: old)
        presenter.triggerQuickAction(try XCTUnwrap(presenter.quickActions.first))
        for _ in 0..<20 where executor.completion == nil { await Task.yield() }
        let completion = try XCTUnwrap(executor.completion)
        presenter.showNotification(title: "New", body: "new", accentColor: .green)
        completion.resume(returning: .copy(old.replacingText("late"), subtitle: "Processed"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(presenter.notificationTitle, "New")
        presenter.dismissNotification()
    }

    func testOldFadeCompletionCannotDismissNewNotification() throws {
        var fades: [() -> Void] = []
        let presenter = NotificationPresenter(animationScheduler: { fades.append($0) })
        presenter.showNotification(title: "Old", body: "old", accentColor: .green, supportsQuickActions: true)
        presenter.triggerQuickAction(try XCTUnwrap(presenter.quickActions.first))
        presenter.showNotification(title: "New", body: "new", accentColor: .green)
        try XCTUnwrap(fades.first)()
        XCTAssertTrue(presenter.isShowingNotification)
        XCTAssertEqual(presenter.notificationTitle, "New")
        presenter.dismissNotification()
    }

    func testFailedNavigationDoesNotCopyAndEmptyCatalogHidesShelf() async throws {
        var copied: [String] = []
        let presenter = NotificationPresenter(copyText: { copied.append($0) }, openURL: { _ in false }, animationScheduler: { $0() })
        presenter.showNotification(title: "Link", body: "https://example.com", accentColor: .green, supportsQuickActions: true)
        presenter.triggerQuickAction(try XCTUnwrap(presenter.quickActions.first { $0.id == "search_web" }))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(presenter.notificationTitle, "Quick Action Failed")
        presenter.showNotification(title: "Empty", body: "hello", accentColor: .green, supportsQuickActions: true, quickActions: [])
        XCTAssertFalse(presenter.supportsQuickActions)
        presenter.dismissNotification()
    }

    func testCanonicalRowsSurvivePresenterChainingAndPreviewIsNotInput() async throws {
        var copied: [String] = []
        let presenter = NotificationPresenter(copyText: { copied.append($0) }, animationScheduler: { $0() })
        let context = ActionContext(payload: .table(.init(rows: [["A", "B"], ["1", "2"]])))
        presenter.showNotification(title: "Table", body: "truncated preview", accentColor: .green, supportsQuickActions: true, actionContext: context)
        presenter.triggerQuickAction(try XCTUnwrap(presenter.quickActions.first { $0.id == "table_csv" }))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(copied, ["A,B\r\n1,2"])
        XCTAssertEqual(presenter.currentActionContext?.payload, context.payload)
        presenter.triggerQuickAction(try XCTUnwrap(presenter.quickActions.first { $0.id == "table_markdown" }))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(copied.last, "|  |  |\n| --- | --- |\n| A | B |\n| 1 | 2 |")
        presenter.dismissNotification()
    }
}
