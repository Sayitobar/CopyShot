import Testing
import SwiftUI
import Combine
import AppKit
@testable import CopyShot

@Suite("Notification presentation options", .serialized)
@MainActor
struct NotificationPresenterTests {
    @Test("An explicit action list replaces generated defaults")
    func usesProvidedQuickActions() {
        let presenter = NotificationPresenter(configProvider: { QuickActionsConfig() })
        let custom = QuickAction(id: "custom", title: "Custom", icon: .system("star"), shortcutNumber: 1)
        presenter.showNotification(
            title: "Test", body: "hello", accentColor: .green,
            supportsQuickActions: true, quickActions: [custom]
        )
        #expect(presenter.quickActions.map(\.id) == ["custom"])
        #expect(presenter.supportsQuickActions)
        presenter.dismissNotification()
    }

    @Test("An explicit duration is scheduled and retained when the timer restarts")
    func usesProvidedDuration() {
        var scheduledDurations: [TimeInterval] = []
        let presenter = NotificationPresenter(dismissScheduler: { duration, _ in
            scheduledDurations.append(duration)
            return AnyCancellable {}
        })
        presenter.showNotification(title: "Test", body: "hello", accentColor: .green, duration: 0.05)
        defer { presenter.dismissNotification() }
        presenter.startDismissTimer()
        #expect(scheduledDurations == [0.05, 0.05])
    }

    @Test("Vertical transparent HUD margins pass clicks through while the visible box receives them")
    func visibleHUDHitBounds() {
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 87), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 88), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 200), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 211), windowHeight: 200, visibleBoxHeight: 78
        ))
    }
}
