import AppKit
import SwiftUI

enum HUDRegion: Hashable { case notification, handle }

/// Tracks only the live view's bounds, independently of SwiftUI's hidden sizing probes.
struct HUDHoverRegion: NSViewRepresentable {
    var enabled = true
    let onHover: (Bool) -> Void
    let onFrameChange: (NSRect?) -> Void

    func makeNSView(context: Context) -> HUDHoverTrackingView { HUDHoverTrackingView() }

    func updateNSView(_ view: HUDHoverTrackingView, context: Context) {
        view.onHover = onHover
        view.onFrameChange = onFrameChange
        view.enabled = enabled
        view.updateTrackingAreas()
    }

    static func dismantleNSView(_ view: HUDHoverTrackingView, coordinator: ()) {
        view.enabled = false
        view.updateTrackingAreas()
    }
}

final class HUDHoverTrackingView: NSView {
    var onHover: ((Bool) -> Void)?
    var onFrameChange: ((NSRect?) -> Void)?
    var enabled = true
    private var area: NSTrackingArea?
    private var lastFrame: NSRect?
    private var isHovered = false
    private var updateScheduled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Since macOS 14, an unclipped NSView's visibleRect can exceed its bounds.
        // A tracking background must never inherit the whole holding window.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { super.init(coder: coder); clipsToBounds = true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !enabled, let area { removeTrackingArea(area); self.area = nil }
        if enabled && area == nil {
            let area = NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }
        scheduleUpdate()
    }

    override func layout() { super.layout(); scheduleUpdate() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); scheduleUpdate() }
    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); scheduleUpdate() }
    override func setBoundsSize(_ newSize: NSSize) { super.setBoundsSize(newSize); scheduleUpdate() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowGeometryChanged), name: name, object: window)
            }
        }
        scheduleUpdate()
    }

    @objc private func windowGeometryChanged() { scheduleUpdate() }
    override func mouseEntered(with event: NSEvent) { updateRegion(event: event) }
    override func mouseExited(with event: NSEvent) { updateRegion(event: event) }
    override func mouseMoved(with event: NSEvent) { updateRegion(event: event) }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.updateRegion()
        }
    }

    private func updateRegion(event: NSEvent? = nil) {
        let pointer: NSPoint
        if let event, let eventWindow = event.window ?? window {
            pointer = eventWindow.convertPoint(toScreen: event.locationInWindow)
        } else { pointer = NSEvent.mouseLocation }
        let frame: NSRect?
        let clippedBounds = bounds.intersection(visibleRect)
        if enabled, let window, window.isVisible, !clippedBounds.isEmpty {
            frame = window.convertToScreen(convert(clippedBounds, to: nil))
        } else { frame = nil }
        if frame != lastFrame { lastFrame = frame; onFrameChange?(frame) }
        let hovering = frame?.contains(pointer) ?? false
        if hovering != isHovered { isHovered = hovering; onHover?(hovering) }
    }
}
