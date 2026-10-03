import Testing
import SwiftUI
import Combine
import AppKit
@testable import CopyShot

@Suite("Notification presentation options", .serialized)
@MainActor
struct NotificationPresenterTests {
    @Test("Dismissal releases the hosted HUD and its capture payload")
    func dismissalReleasesContent() throws {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let presenter = NotificationPresenter()
        presenter.showNotification(title: "Test", body: "preview", fullBody: String(repeating: "payload", count: 1000),
                                   accentColor: .green, supportsQuickActions: true)
        let window = try #require(NSApp.windows.first {
            !before.contains(ObjectIdentifier($0)) && $0.contentView is NotificationHostingView<AnyView>
        })
        presenter.dismissNotification()
        #expect(window.contentView == nil)
        #expect(presenter.currentActionContext == nil)
        #expect(presenter.notificationFullBody == nil)
        #expect(presenter.quickActions.isEmpty)
    }

    @Test("A notification without Quick Actions does not retain an action catalog")
    func noUnusedActionCatalog() {
        let presenter = NotificationPresenter()
        presenter.showNotification(title: "Cancelled", body: "No capture.", accentColor: .red)
        defer { presenter.dismissNotification() }
        #expect(presenter.quickActions.isEmpty)
        #expect(!presenter.supportsQuickActions)
    }

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
