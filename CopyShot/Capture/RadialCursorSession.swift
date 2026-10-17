import CoreGraphics

/// Owns the cursor association for one radial gesture. System calls are injectable
/// so lifecycle tests never move or disconnect the user's real pointer.
final class RadialCursorSession {
    private let associate: (Bool) -> CGError
    private let warp: (CGPoint) -> CGError
    private let reportFailure: (DiagnosticEvent, CGError) -> Void
    private var origin: CGPoint?

    init(associate: @escaping (Bool) -> CGError = { CGAssociateMouseAndMouseCursorPosition($0 ? 1 : 0) },
         warp: @escaping (CGPoint) -> CGError = CGWarpMouseCursorPosition,
         reportFailure: @escaping (DiagnosticEvent, CGError) -> Void = {
             DiagnosticLog.shared.record($0, code: Int($1.rawValue))
         }) {
        self.associate = associate
        self.warp = warp
        self.reportFailure = reportFailure
    }

    func begin(at quartzPoint: CGPoint) {
        finish()
        origin = quartzPoint
        check(associate(false), event: .cursorDisconnectFailed)
    }

    func finish() {
        guard let origin else { return }
        // Clear ownership before callbacks: teardown and late mouse-up must be no-ops.
        self.origin = nil
        check(warp(origin), event: .cursorRestoreFailed)
        check(associate(true), event: .cursorReconnectFailed)
        // Absolute-input drivers may resynchronize on reconnect. Restore once more
        // in the same call, without posting mouse events or scheduling a later warp.
        check(warp(origin), event: .cursorRestoreFailed)
        // Known limitation reported in VirtualBuddy with a macOS 26 guest: the
        // next host-origin mouse event can replace this position. Release-time
        // warps do not resolve that later jump. Keep the frozen radial behavior;
        // no moving-crosshair fallback or repeated/delayed warps are intended.
        // See docs/MACOS_COMPATIBILITY.md; native macOS 26 cause is unconfirmed.
    }

    private func check(_ result: CGError, event: DiagnosticEvent) {
        if result != .success { reportFailure(event, result) }
    }
}
