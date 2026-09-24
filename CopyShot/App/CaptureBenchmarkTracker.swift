//
//  CaptureBenchmarkTracker.swift
//  CopyShot
//
//  Created for CopyShot.
//

import Foundation

#if DEBUG
/// Compiles only in DEBUG builds; stripped entirely in RELEASE builds.
final class CaptureBenchmarkTracker: @unchecked Sendable {
    static let shared = CaptureBenchmarkTracker()
    
    private let lock = NSLock()
    private var mouseReleaseTime: ContinuousClock.Instant?
    private var captureAcquiredTime: ContinuousClock.Instant?
    private var ocrCompletedTime: ContinuousClock.Instant?
    
    private init() {}
    
    func recordMouseRelease() {
        lock.lock()
        defer { lock.unlock() }
        mouseReleaseTime = ContinuousClock.now
        captureAcquiredTime = nil
        ocrCompletedTime = nil
    }
    
    func recordCaptureAcquired() {
        lock.lock()
        defer { lock.unlock() }
        captureAcquiredTime = ContinuousClock.now
    }
    
    func recordOCRCompleted() {
        lock.lock()
        defer { lock.unlock() }
        ocrCompletedTime = ContinuousClock.now
    }
    
    func recordHUDDisplayed() {
        let hudTime = ContinuousClock.now
        
        lock.lock()
        guard let release = mouseReleaseTime,
              let capture = captureAcquiredTime,
              let ocr = ocrCompletedTime else {
            lock.unlock()
            return
        }
        // Reset state so subsequent captures are tracked freshly
        mouseReleaseTime = nil
        captureAcquiredTime = nil
        ocrCompletedTime = nil
        lock.unlock()
        
        let captureMs = Double((capture - release).components.attoseconds) / 1_000_000_000_000_000.0
        let ocrMs = Double((ocr - capture).components.attoseconds) / 1_000_000_000_000_000.0
        let hudMs = Double((hudTime - ocr).components.attoseconds) / 1_000_000_000_000_000.0
        let totalMs = Double((hudTime - release).components.attoseconds) / 1_000_000_000_000_000.0
        
        let output = String(
            format: """
            
            ========================================================================
            [CopyShot Live Latency Breakdown]
                1. Mouse Release ➔ Screenshot Acquired: %6.1f ms  (SCScreenshotManager)
                2. Screenshot ➔ OCR Recognition:        %6.1f ms  (Apple Vision)
                3. OCR ➔ Clipboard & HUD Visible:       %6.1f ms  (AppKit Presentation)
                ──────────────────────────────────────────────────────────────────
                TOTAL (Mouse Release ➔ Notification):   %6.1f ms
            ========================================================================
            
            """,
            captureMs, ocrMs, hudMs, totalMs
        )
        
        print(output)
    }
}
#endif
