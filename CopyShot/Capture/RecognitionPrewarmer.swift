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
    private enum Engine: Hashable {
        case ocr(OCRService.Configuration), barcode, formula
    }
    private let formulaService: FormulaRecognizing
    private let settings: SettingsManager
    private let ocrPrewarm: (OCRService.Configuration, @escaping (Bool) -> Void) -> Void
    private var warmedEngines = Set<Engine>()
    private var sessionID = UUID()
    private(set) var warmedModesInSession = Set<CaptureMode>()

    init(formulaService: FormulaRecognizing, settings: SettingsManager = .shared,
         ocrPrewarm: @escaping (OCRService.Configuration, @escaping (Bool) -> Void) -> Void = {
             OCRService.prewarm(configuration: $0, completion: $1)
         }) {
        self.formulaService = formulaService
        self.settings = settings
        self.ocrPrewarm = ocrPrewarm
    }

    /// Resets per-session prewarm tracking when a new capture session starts or ends.
    func resetSession() {
        warmedModesInSession.removeAll()
        warmedEngines.removeAll()
        sessionID = UUID()
    }

    /// Asynchronously prewarms the engine for the active capture mode, deduplicating within the session.
    func prewarm(mode: CaptureMode) {
        guard settings.prewarmRecognition else { return }
        warmedModesInSession.insert(mode)
        let engine: Engine
        switch mode {
        case .standardOCR, .table: engine = .ocr(.init(settings: settings))
        case .qrBarcode: engine = .barcode
        case .latex: engine = .formula
        }
        guard warmedEngines.insert(engine).inserted else { return }
        let session = sessionID
        let finished: (Bool) -> Void = { [weak self] success in
            Task { @MainActor in
                guard let self, self.sessionID == session, !success else { return }
                self.warmedEngines.remove(engine)
                self.warmedModesInSession.remove(mode)
            }
        }
        switch mode {
        case .standardOCR, .table:
            if case .ocr(let configuration) = engine { ocrPrewarm(configuration, finished) }
        case .qrBarcode:
            BarcodeRecognitionService.prewarm(completion: finished)
        case .latex:
            formulaService.prewarm(completion: finished)
        }
    }
}
