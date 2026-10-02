//
//  RecognitionPrewarmer.swift
//  CopyShot
//
//  Created for CopyShot.
//

import AppKit
import Vision

/// Coordinates mode-aware, asynchronous prewarming for OCR, Barcode, and LaTeX recognition engines.
/// Guarantees that prewarm work never blocks the main UI and only runs when enabled in Settings.
@MainActor
final class RecognitionPrewarmer {
    private let formulaService: FormulaRecognizing
    private(set) var warmedModesInSession = Set<CaptureMode>()

    init(formulaService: FormulaRecognizing) {
        self.formulaService = formulaService
    }

    /// Resets per-session prewarm tracking when a new capture session starts or ends.
    func resetSession() {
        warmedModesInSession.removeAll()
    }

    /// Asynchronously prewarms the engine for the active capture mode, deduplicating within the session.
    func prewarm(mode: CaptureMode) {
        guard SettingsManager.shared.prewarmRecognition else { return }
        guard !warmedModesInSession.contains(mode) else { return }
        warmedModesInSession.insert(mode)

        switch mode {
        case .standardOCR, .table:
            OCRService.prewarm()
        case .qrBarcode:
            BarcodeRecognitionService.prewarm()
        case .latex:
            formulaService.prewarm()
        }
    }
}
