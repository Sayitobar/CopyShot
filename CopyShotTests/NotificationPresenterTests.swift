import Testing
import SwiftUI
import Combine
import AppKit
@testable import CopyShot

@Suite("Notification presentation options", .serialized)
@MainActor
struct NotificationPresenterTests {
    @Test("A shelf shadow canvas keeps its requested frame at the menu-bar boundary")
    func shelfCanvasIsNotShiftedByAppKit() throws {
        let screen = try #require(NSScreen.screens.first)
        let requested = NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY + 21 - 100,
                               width: 272, height: 100)
        let window = NotificationHUDWindow(contentRect: requested, styleMask: .borderless,
                                           backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.allowsShadowCanvasOutsideVisibleFrame = true
        window.contentView = NSView(frame: NSRect(origin: .zero, size: requested.size))
        defer { window.orderOut(nil); window.contentView = nil }
        window.orderFrontRegardless()
        window.setFrame(requested, display: true)
        #expect(window.frame == requested)
    }

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

    @Test("Transparent HUD margins pass clicks through on both axes")
    func visibleHUDHitBounds() {
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 87), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 88), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 120), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 200), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 0, y: 120), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: NotificationHUDLayout.width - 1, y: 120), windowHeight: 200, visibleBoxHeight: 78
        ))
        #expect(!NotificationPresenter.isPointInVisibleBox(
            NSPoint(x: 100, y: 211), windowHeight: 200, visibleBoxHeight: 78
        ))
    }

    @Test("Collapsing the HUD releases the former expanded region")
    func collapsedHUDDoesNotKeepExpandedBounds() {
        let point = NSPoint(x: 100, y: 700)
        #expect(NotificationPresenter.isPointInVisibleBox(point, windowHeight: 800, visibleBoxHeight: 300))
        #expect(!NotificationPresenter.isPointInVisibleBox(point, windowHeight: 800, visibleBoxHeight: 78))
    }

    @Test("Native hover uses event coordinates and releases a region after its view shrinks")
    func nativeHoverTracksCurrentBounds() async throws {
        let cursor = NSEvent.mouseLocation
        // The physical pointer matches the synthetic point initially and is guaranteed
        // to lie outside the compact region after shrinking (without moving user input).
        let window = NSWindow(contentRect: NSRect(x: cursor.x - 100, y: cursor.y - 200, width: 344, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 344, height: 300))
        let region = HUDHoverTrackingView(frame: container.bounds)
        container.addSubview(region)
        window.contentView = container
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        var transitions: [Bool] = []
        region.onHover = { transitions.append($0) }
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 100, y: 200),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        region.mouseMoved(with: event)
        region.setFrameSize(NSSize(width: 344, height: 78))
        try await Task.sleep(for: .milliseconds(30))
        #expect(transitions == [true, false])
        #expect(region.hitTest(NSPoint(x: 20, y: 20)) == nil)
    }

    @Test("Hosted native hover geometry is limited to the compact notification")
    func hostedCompactHoverGeometry() async throws {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let presenter = NotificationPresenter()
        presenter.showNotification(title: "Fixture", body: "Short preview", fullBody: String(repeating: "Long body\n", count: 36),
                                   accentColor: .green, supportsQuickActions: true)
        defer { presenter.dismissNotification() }
        let window = try #require(NSApp.windows.first {
            !before.contains(ObjectIdentifier($0)) && $0.contentView is NotificationHostingView<AnyView>
        })
        func regions(_ view: NSView) -> [HUDHoverTrackingView] {
            (view as? HUDHoverTrackingView).map { [$0] } ?? view.subviews.flatMap(regions)
        }
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let root = try #require(window.contentView)
        let trackers = regions(root)
        #expect(trackers.count == 2)
        for tracker in trackers {
            #expect(tracker.bounds.height < 150, "A compact one-line HUD must not track the full expanded holding window.")
            #expect(tracker.visibleRect.height <= tracker.bounds.height)
            if tracker.bounds.width < 100 {
                // A 4pt blur with a -1pt horizontal offset needs a 13pt left drawing budget.
                #expect(tracker.convert(tracker.bounds, to: root).minX >= 13)
            }
        }
    }
}
