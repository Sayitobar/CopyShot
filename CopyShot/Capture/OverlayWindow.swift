//
//  OverlayWindow.swift
//  CopyShot
//
//  Created by Mac on 14.06.25.
//

import AppKit
import SwiftUI

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
            CGAssociateMouseAndMouseCursorPosition(1)
            // If Escape is pressed, call our closure.
            onEscape?()
        } else {
            // For any other key, do nothing.
            super.keyDown(with: event)
        }
    }
}

// Custom HostingView that accepts first mouse to prevent click-through/stutter
class ActionHostingView<Content: View>: NSHostingView<Content> {
    var onRightMouseDown: ((CGPoint, CGSize) -> Void)?
    var onRightMouseDragged: ((CGPoint) -> Void)?
    var onRightMouseUp: ((CGPoint) -> Void)?
    private var initialLocalPoint: CGPoint?
    private var accumulatedOffset: CGPoint = .zero
    private var isMouseDisassociated = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private func localPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    private func restoreCursorAssociation() {
        if isMouseDisassociated {
            CGAssociateMouseAndMouseCursorPosition(1)
            isMouseDisassociated = false
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let callPoint = localPoint(for: event)
        initialLocalPoint = callPoint
        accumulatedOffset = .zero

        // Freeze cursor position at the call position while continuing to receive input vectors
        CGAssociateMouseAndMouseCursorPosition(0)
        isMouseDisassociated = true

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
        restoreCursorAssociation()
        let effectivePoint: CGPoint
        if let initialLocalPoint {
            effectivePoint = CGPoint(
                x: initialLocalPoint.x + accumulatedOffset.x,
                y: initialLocalPoint.y + accumulatedOffset.y
            )
        } else {
            effectivePoint = localPoint(for: event)
        }
        self.initialLocalPoint = nil
        self.accumulatedOffset = .zero
        onRightMouseUp?(effectivePoint)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            restoreCursorAssociation()
        }
    }

    deinit {
        restoreCursorAssociation()
    }
}
