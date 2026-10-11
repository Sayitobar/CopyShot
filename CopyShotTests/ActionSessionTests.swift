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
    func testTranslationKeepsWaitingHUDVisibleAndClosingSuppressesLateCopy() async throws {
        let executor = DeferredActionExecutor()
        var copied: [String] = []
        let presenter = NotificationPresenter(actionExecutor: executor, copyText: { copied.append($0) }, animationScheduler: { $0() })
        let context = ActionContext(payload: .standardText("Hallo"))
        presenter.showNotification(title: "Capture", body: context.text, accentColor: .green,
                                   supportsQuickActions: true, actionContext: context)
        let action = QuickAction(id: "translation", title: "Translate", icon: .system("character.bubble"), shortcutNumber: 1, operation: .translate("en"))
        presenter.triggerQuickAction(action)
        XCTAssertTrue(presenter.isRunningAction)
        XCTAssertTrue(presenter.isShowingNotification)
        XCTAssertNil(presenter.actionForShortcut(1))
        for _ in 0..<30 where executor.completion == nil { await Task.yield() }
        let completion = try XCTUnwrap(executor.completion)
        presenter.dismissNotification()
        completion.resume(returning: .copy(context.replacingText("Hello"), subtitle: "Translated"))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(copied.isEmpty)
        XCTAssertFalse(presenter.isShowingNotification)
        XCTAssertFalse(presenter.isRunningAction)
    }

    func testEmptyInspectionOpensWithoutCopyingAndLateInspectionDoesNotOpen() async throws {
        var config = QuickActionsConfig()
        config.disabledActionIds.removeAll { $0 == "inspect_capture" }
        var copied: [String] = []
        var opened: [OCRInspection] = []
        let record = OCRInspectionTests.record(text: "")
        let context = ActionContext(payload: .standardText(""), inspection: record)
        let presenter = NotificationPresenter(copyText: { copied.append($0) }, animationScheduler: { $0() },
                                              presentInspection: { opened.append($0); XCTAssertEqual($1, "") },
                                              configProvider: { config })
        presenter.showNotification(title: "No Text Found", body: "Empty", accentColor: .blue,
                                   supportsQuickActions: true, actionContext: context)
        presenter.triggerQuickAction(try XCTUnwrap(presenter.quickActions.first))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened.first === record)
        XCTAssertTrue(copied.isEmpty)
        XCTAssertFalse(presenter.isShowingNotification)

        let executor = DeferredActionExecutor()
        let delayed = NotificationPresenter(actionExecutor: executor, animationScheduler: { $0() },
                                            presentInspection: { record, _ in opened.append(record) }, configProvider: { config })
        delayed.showNotification(title: "Old", body: "Empty", accentColor: .blue,
                                 supportsQuickActions: true, actionContext: context)
        delayed.triggerQuickAction(try XCTUnwrap(delayed.quickActions.first))
        for _ in 0..<20 where executor.completion == nil { await Task.yield() }
        let completion = try XCTUnwrap(executor.completion)
        delayed.showNotification(title: "New", body: "New", accentColor: .blue)
        completion.resume(returning: .inspectCapture(record, currentText: ""))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(delayed.notificationTitle, "New")
        delayed.dismissNotification()
    }

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
