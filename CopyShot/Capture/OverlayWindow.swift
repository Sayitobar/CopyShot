//
//  OverlayWindow.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import AppKit
import SwiftUI

protocol RadialGestureCancelling: AnyObject {
    func cancelRadialGesture()
}

// We create a custom NSWindow subclass.
class OverlayWindow: NSWindow {
    
    var onEscape: (() -> Void)?
    
    // We override this to allow the window to receive keyboard and mouse events.
    override var canBecomeKey: Bool {
        return true
    }
    
    // We add this override to allow the window to be the main window of the application.
    // For a single-window utility, this can be crucial.
    override var canBecomeMain: Bool {
        return true
    }
    
    // This function is called whenever a key is pressed while the window is key.
    override func keyDown(with event: NSEvent) {
        // The key code for the Escape key is 53.
        if event.keyCode == 53 {
            (contentView as? RadialGestureCancelling)?.cancelRadialGesture()
            // If Escape is pressed, call our closure.
            onEscape?()
        } else {
            // For any other key, do nothing.
            super.keyDown(with: event)
        }
    }

    override func resignKey() {
        (contentView as? RadialGestureCancelling)?.cancelRadialGesture()
        super.resignKey()
    }

    override func orderOut(_ sender: Any?) {
        (contentView as? RadialGestureCancelling)?.cancelRadialGesture()
        super.orderOut(sender)
    }
}

// Custom HostingView that accepts first mouse to prevent click-through/stutter
class ActionHostingView<Content: View>: NSHostingView<Content>, RadialGestureCancelling {
    var onRightMouseDown: ((CGPoint, CGSize) -> Void)?
    var onRightMouseDragged: ((CGPoint) -> Void)?
    var onRightMouseUp: ((CGPoint) -> Void)?
    var onRightMouseCancel: (() -> Void)?
    private var initialLocalPoint: CGPoint?
    private var accumulatedOffset: CGPoint = .zero
    private var cursorSession = RadialCursorSession()

    convenience init(rootView: Content, cursorSession: RadialCursorSession) {
        self.init(rootView: rootView)
        self.cursorSession = cursorSession
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private func localPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    func cancelRadialGesture() {
        let wasTracking = initialLocalPoint != nil
        initialLocalPoint = nil
        accumulatedOffset = .zero
        cursorSession.finish()
        if wasTracking { onRightMouseCancel?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right-clicks can target a non-key overlay on another display. Give it
        // Escape/focus-loss ownership before disconnecting the global cursor.
        window?.makeKey()
        cancelRadialGesture()
        let callPoint = localPoint(for: event)
        initialLocalPoint = callPoint
        accumulatedOffset = .zero

        // Freeze cursor position at the call position while continuing to receive input vectors
        if let quartzPoint = event.cgEvent?.location ?? CGEvent(source: nil)?.location {
            cursorSession.begin(at: quartzPoint)
        }

        onRightMouseDown?(callPoint, bounds.size)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let initialLocalPoint else { return }
        accumulatedOffset.x += event.deltaX
        accumulatedOffset.y += event.deltaY
        let effectivePoint = CGPoint(
            x: initialLocalPoint.x + accumulatedOffset.x,
            y: initialLocalPoint.y + accumulatedOffset.y
        )
        onRightMouseDragged?(effectivePoint)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let initialLocalPoint else { return }
        let effectivePoint = CGPoint(x: initialLocalPoint.x + accumulatedOffset.x,
                                     y: initialLocalPoint.y + accumulatedOffset.y)
        self.initialLocalPoint = nil
        self.accumulatedOffset = .zero
        cursorSession.finish()
        onRightMouseUp?(effectivePoint)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelRadialGesture() }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        cursorSession.finish()
    }
}
