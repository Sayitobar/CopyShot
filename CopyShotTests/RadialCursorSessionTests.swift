import Testing
import CoreGraphics
import AppKit
import SwiftUI
@testable import CopyShot

@Suite("Radial cursor restoration")
@MainActor
struct RadialCursorSessionTests {
    private final class CursorDevice {
        var position = CGPoint.zero
        var connected = true
        var reconnectPosition = CGPoint(x: 900, y: 700)
        var disconnectResult: CGError = .success
        var firstWarpResult: CGError = .success
        var warpCount = 0
        var failures: [DiagnosticEvent] = []

        func session() -> RadialCursorSession {
            RadialCursorSession(associate: { connected in
                if !connected, self.disconnectResult != .success { return self.disconnectResult }
                self.connected = connected
                // Model a VM/input driver resynchronizing absolute position on reconnect.
                if connected { self.position = self.reconnectPosition }
                return .success
            }, warp: { point in
                self.warpCount += 1
                if self.warpCount == 1, self.firstWarpResult != .success { return self.firstWarpResult }
                self.position = point
                return .success
            }, reportFailure: { event, _ in self.failures.append(event) })
        }
    }

    @Test("Reconnect resynchronization cannot displace the radial invocation point")
    func restoresAfterDriverResynchronizes() {
        let device = CursorDevice()
        let session = device.session()
        let anchor = CGPoint(x: 120, y: 230)
        session.begin(at: anchor)
        session.finish()
        #expect(device.connected)
        #expect(device.position == anchor)
    }

    @Test("Quartz coordinates on displays above or left of the primary are preserved")
    func preservesGlobalCoordinates() {
        let device = CursorDevice()
        let session = device.session()
        let anchor = CGPoint(x: -320.5, y: -840.25)
        session.begin(at: anchor)
        session.finish()
        #expect(device.position == anchor)
    }

    @Test("Repeated cleanup cannot warp a pointer that the user has moved afterward")
    func cleanupIsIdempotent() {
        let device = CursorDevice()
        let session = device.session()
        session.begin(at: CGPoint(x: 10, y: 20))
        session.finish()
        let laterPosition = CGPoint(x: 730, y: 410)
        device.position = laterPosition
        session.finish()
        #expect(device.position == laterPosition)
        #expect(device.connected)
    }

    @Test("A failed disconnect still restores the invocation point and reports only a safe event")
    func failedDisconnectFallsBackToRestoration() {
        let device = CursorDevice()
        device.disconnectResult = .cannotComplete
        let session = device.session()
        let anchor = CGPoint(x: 10, y: 20)
        session.begin(at: anchor)
        session.finish()
        #expect(device.position == anchor)
        #expect(device.connected)
        #expect(device.failures == [.cursorDisconnectFailed])
    }

    @Test("A failed first warp never skips reconnect or the final restoration")
    func firstWarpFailureStillReconnects() {
        let device = CursorDevice()
        device.firstWarpResult = .cannotComplete
        let session = device.session()
        let anchor = CGPoint(x: 30, y: 50)
        session.begin(at: anchor)
        session.finish()
        #expect(device.position == anchor)
        #expect(device.connected)
        #expect(device.failures == [.cursorRestoreFailed])
    }

    private func mouseEvent(_ type: CGEventType, at point: CGPoint, deltaX: Int64 = 0) throws -> NSEvent {
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                                        mouseCursorPosition: point, mouseButton: .right))
        event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        return try #require(NSEvent(cgEvent: event))
    }

    private final class FocusTrackingWindow: OverlayWindow {
        var cursorWasConnected: (() -> Bool)?
        var receivedFocusBeforeFreeze = false

        override func makeKey() {
            receivedFocusBeforeFreeze = cursorWasConnected?() ?? false
        }
    }

    @Test("The clicked display owns keyboard cancellation before its radial gesture freezes the cursor")
    func receivingOverlayOwnsCancellation() throws {
        let device = CursorDevice()
        let host = ActionHostingView(rootView: Color.clear, cursorSession: device.session())
        let window = FocusTrackingWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                         styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.cursorWasConnected = { device.connected }
        defer { window.contentView = nil }
        host.rightMouseDown(with: try mouseEvent(.rightMouseDown, at: CGPoint(x: 120, y: 230)))
        #expect(window.receivedFocusBeforeFreeze)
        #expect(!device.connected)
        window.resignKey()
        #expect(device.connected)
    }

    @Test("Release selects using relative motion while restoring the original global cursor point")
    func hostingViewKeepsVirtualSelectionSeparateFromCursor() throws {
        let device = CursorDevice()
        let host = ActionHostingView(rootView: Color.clear, cursorSession: device.session())
        host.setFrameSize(CGSize(width: 600, height: 400))
        let anchor = CGPoint(x: 120, y: 230)
        var initialPoint: CGPoint?
        var releasedPoint: CGPoint?
        host.onRightMouseDown = { point, _ in initialPoint = point }
        host.onRightMouseUp = { releasedPoint = $0 }
        host.rightMouseDown(with: try mouseEvent(.rightMouseDown, at: anchor))
        host.rightMouseDragged(with: try mouseEvent(.rightMouseDragged, at: anchor, deltaX: 80))
        host.rightMouseUp(with: try mouseEvent(.rightMouseUp, at: CGPoint(x: 200, y: 230)))
        let start = try #require(initialPoint)
        #expect(releasedPoint == CGPoint(x: start.x + 80, y: start.y))
        #expect(device.position == anchor)
        #expect(device.connected)
    }

    enum Cancellation: CaseIterable { case escape, orderOut, resignKey, detach }

    @Test("Every overlay cancellation restores the cursor and ignores a late release", arguments: Cancellation.allCases)
    func cancellationPaths(_ path: Cancellation) throws {
        let device = CursorDevice()
        let host = ActionHostingView(rootView: Color.clear, cursorSession: device.session())
        let window = OverlayWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil }
        let anchor = CGPoint(x: 180, y: 240)
        var cancellations = 0
        var completions = 0
        host.onRightMouseCancel = { cancellations += 1 }
        host.onRightMouseUp = { _ in completions += 1 }
        host.rightMouseDown(with: try mouseEvent(.rightMouseDown, at: anchor))
        switch path {
        case .escape:
            let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
            window.keyDown(with: escape)
        case .orderOut: window.orderOut(nil)
        case .resignKey: window.resignKey()
        case .detach: window.contentView = nil
        }
        #expect(device.connected)
        #expect(device.position == anchor)
        #expect(cancellations == 1)
        let laterPosition = CGPoint(x: 720, y: 420)
        device.position = laterPosition
        host.rightMouseUp(with: try mouseEvent(.rightMouseUp, at: laterPosition))
        host.cancelRadialGesture()
        #expect(completions == 0)
        #expect(cancellations == 1)
        #expect(device.position == laterPosition)
    }

    @Test("Deinitializing an active hosting view reconnects and restores its cursor")
    func deinitRestoresCursor() throws {
        let device = CursorDevice()
        let anchor = CGPoint(x: 25, y: 45)
        weak var releasedHost: ActionHostingView<Color>?
        // AppKit can retain the hosting view until its autorelease pool drains.
        try autoreleasepool {
            let host = ActionHostingView(rootView: Color.clear, cursorSession: device.session())
            releasedHost = host
            host.rightMouseDown(with: try mouseEvent(.rightMouseDown, at: anchor))
        }
        #expect(releasedHost == nil)
        #expect(device.connected)
        #expect(device.position == anchor)
    }
}
