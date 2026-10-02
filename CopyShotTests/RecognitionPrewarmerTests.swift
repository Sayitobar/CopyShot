//
//  RecognitionPrewarmerTests.swift
//  CopyShotTests
//
//  Created for CopyShot.
//

import AppKit
import Testing
@testable import CopyShot

private final class MockFormulaService: FormulaRecognizing {
    private(set) var prewarmCallCount = 0
    private(set) var recognizeCallCount = 0

    func prewarm() {
        prewarmCallCount += 1
    }

    func recognize(_ image: CGImage, completion: @escaping (Result<FormulaResult, Error>) -> Void) {
        recognizeCallCount += 1
        completion(.success(FormulaResult(formula: "E = mc^2")))
    }
}

@Suite("Recognition Prewarming")
@MainActor
struct RecognitionPrewarmerTests {

    @Test("Prewarming is skipped when disabled in Settings")
    func testPrewarmRespectsSettingsToggle() throws {
        let suite = "CopyShotTests.prewarmToggle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        settings.prewarmRecognition = false

        // Temporarily override shared settings for test duration
        let originalSharedSetting = SettingsManager.shared.prewarmRecognition
        defer { SettingsManager.shared.prewarmRecognition = originalSharedSetting }
        SettingsManager.shared.prewarmRecognition = false

        let mockFormula = MockFormulaService()
        let prewarmer = RecognitionPrewarmer(formulaService: mockFormula)

        prewarmer.prewarm(mode: .latex)
        prewarmer.prewarm(mode: .standardOCR)
        prewarmer.prewarm(mode: .qrBarcode)

        #expect(mockFormula.prewarmCallCount == 0)
        #expect(prewarmer.warmedModesInSession.isEmpty)
    }

    @Test("Prewarming deduplicates redundant requests within the same capture session")
    func testPrewarmDeduplicationWithinSession() throws {
        let originalSharedSetting = SettingsManager.shared.prewarmRecognition
        defer { SettingsManager.shared.prewarmRecognition = originalSharedSetting }
        SettingsManager.shared.prewarmRecognition = true

        let mockFormula = MockFormulaService()
        let prewarmer = RecognitionPrewarmer(formulaService: mockFormula)

        // First prewarm call should record mode and dispatch
        prewarmer.prewarm(mode: .latex)
        #expect(mockFormula.prewarmCallCount == 1)
        #expect(prewarmer.warmedModesInSession.contains(.latex))

        // Second call within same session must be a no-op
        prewarmer.prewarm(mode: .latex)
        #expect(mockFormula.prewarmCallCount == 1)

        // Reset session should allow prewarming again
        prewarmer.resetSession()
        #expect(prewarmer.warmedModesInSession.isEmpty)

        prewarmer.prewarm(mode: .latex)
        #expect(mockFormula.prewarmCallCount == 2)
        #expect(prewarmer.warmedModesInSession.contains(.latex))
    }

    @Test("Prewarming routes across all capture modes correctly")
    func testPrewarmRoutesAllModes() {
        let originalSharedSetting = SettingsManager.shared.prewarmRecognition
        defer { SettingsManager.shared.prewarmRecognition = originalSharedSetting }
        SettingsManager.shared.prewarmRecognition = true

        let mockFormula = MockFormulaService()
        let prewarmer = RecognitionPrewarmer(formulaService: mockFormula)

        prewarmer.prewarm(mode: .standardOCR)
        #expect(prewarmer.warmedModesInSession.contains(.standardOCR))

        prewarmer.prewarm(mode: .qrBarcode)
        #expect(prewarmer.warmedModesInSession.contains(.qrBarcode))

        prewarmer.prewarm(mode: .table)
        #expect(prewarmer.warmedModesInSession.contains(.table))

        prewarmer.prewarm(mode: .latex)
        #expect(prewarmer.warmedModesInSession.contains(.latex))
        #expect(mockFormula.prewarmCallCount == 1)
    }

    @Test("CaptureModeSelection and interaction trigger onModeSelected when slice is selected")
    func testModeSelectionTriggersCallback() {
        var selectedModes: [CaptureMode] = []
        let selection = CaptureModeSelection(mode: .standardOCR) { mode in
            selectedModes.append(mode)
        }

        selection.selectMode(.qrBarcode)
        #expect(selectedModes == [.qrBarcode])
        #expect(selection.mode == .qrBarcode)

        // Radial interaction selection simulation
        let interaction = CaptureModeInteraction(selection: selection)
        let canvas = CGSize(width: 500, height: 500)
        interaction.begin(at: CGPoint(x: 250, y: 250), in: canvas)

        // Move to index 2 (.latex: 12 o'clock + 2 * (2π/4) = 6 o'clock: positive y)
        interaction.move(to: CGPoint(x: 250, y: 350))
        #expect(interaction.candidateIndex != nil)

        interaction.end(at: CGPoint(x: 250, y: 350))
        #expect(selection.mode == .latex)
        #expect(selectedModes.contains(.latex))
    }

    @Test("ScreenCaptureManager lifecycle dispatches prewarm for default mode and resets session")
    func testScreenCaptureManagerPrewarmWiring() {
        let manager = ScreenCaptureManager()
        var prewarmedModes: [CaptureMode] = []
        var sessionResetCount = 0

        manager.onPrewarmRequested = { mode in
            prewarmedModes.append(mode)
        }
        manager.onSessionReset = {
            sessionResetCount += 1
        }

        // When starting capture, it resets the session and prewarms default mode if matching
        let defaultMode = SettingsManager.shared.defaultCaptureMode
        let initialMode = SettingsManager.shared.initialCaptureMode()
        
        manager.startCapture()

        #expect(sessionResetCount == 1)
        if initialMode == defaultMode {
            #expect(prewarmedModes.contains(initialMode))
        }
    }

    @Test("Prewarming does not pollute or deliver results to CapturePipeline")
    func testPrewarmIsolationFromCapturePipeline() throws {
        var deliveredOutcomes: [CapturePipeline.Outcome] = []
        let pipeline = CapturePipeline(
            isLatest: { _ in true },
            recognizers: [
                .standardOCR: { _, completion in
                    completion(.success(.standardText("Real OCR Result")))
                }
            ],
            deliver: { outcome, _ in
                deliveredOutcomes.append(outcome)
            }
        )

        // Execute OCRService prewarm
        OCRService.prewarm()
        BarcodeRecognitionService.prewarm()

        // Wait brief instant on background queue
        Thread.sleep(forTimeInterval: 0.05)

        // Pipeline must receive ZERO deliveries from prewarming
        #expect(deliveredOutcomes.isEmpty)

        // Real capture through pipeline operates cleanly
        let dummyImage = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                   bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        pipeline.completeCapture(image: dummyImage, screen: nil, mode: .standardOCR, requestID: UUID())

        #expect(deliveredOutcomes.count == 1)
        if case .result(let result) = deliveredOutcomes.first,
           case .standardText(let text) = result {
            #expect(text == "Real OCR Result")
        } else {
            Issue.record("Expected Real OCR Result delivered to pipeline")
        }
    }
}
