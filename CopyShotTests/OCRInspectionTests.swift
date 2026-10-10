import XCTest
import AppKit
import CoreText
@testable import CopyShot

@MainActor
final class OCRInspectionTests: XCTestCase {
    static func image(text: String = "CopyShot Inspection") -> CGImage {
        let context = CGContext(data: nil, width: 500, height: 120, bitsPerComponent: 8,
                                bytesPerRow: 2000, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 500, height: 120))
        let string = NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, 28, nil),
            .foregroundColor: NSColor.black.cgColor
        ])
        context.textPosition = CGPoint(x: 20, y: 50)
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
        return context.makeImage()!
    }

    static func record(text: String = "Original") -> OCRInspection {
        let image = image(text: text)
        return OCRInspection(original: image, input: image, preprocessing: .applied,
                             configuration: OCRService.Configuration(), regions: text.isEmpty ? [] : [
                                .init(id: 1, text: text, bounds: CGRect(x: 0.1, y: 0.3, width: 0.6, height: 0.3), confidence: 0.9)
                             ], assembledText: text, timings: .init(preprocessing: 1, recognition: 2, assembly: 0.1))
    }

    func testInspectionIsDisabledByDefaultAndRequiresARecord() {
        var config = QuickActionsConfig()
        XCTAssertFalse(config.inspectionEnabled)
        XCTAssertTrue(config.disabledActionIds.contains("inspect_capture"))
        config.disabledActionIds.removeAll { $0 == "inspect_capture" }
        XCTAssertTrue(config.inspectionEnabled)
        XCTAssertFalse(ActionRegistry.shared.actions(context: .init(payload: .standardText("hello")), config: config)
            .contains { $0.id == "inspect_capture" })
        let context = ActionContext(payload: .standardText("hello"), inspection: Self.record())
        XCTAssertTrue(ActionRegistry.shared.actions(context: context, config: config).contains { $0.id == "inspect_capture" })
        config.isEnabled = false
        XCTAssertFalse(config.inspectionEnabled)
    }

    func testTransformPreservesOriginalRecordAndSession() {
        let record = Self.record()
        let context = ActionContext(payload: .standardText(record.assembledText), inspection: record)
        let updated = context.replacingText("ORIGINAL")
        XCTAssertTrue(updated.inspection === record)
        XCTAssertEqual(updated.sessionID, context.sessionID)
        XCTAssertEqual(record.assembledText, "Original")
        XCTAssertEqual(updated.text, "ORIGINAL")
    }

    func testInspectionOptInPersistsWhenSettingsReload() {
        let suite = "CopyShot.InspectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        XCTAssertFalse(settings.quickActionsConfig.inspectionEnabled)
        settings.quickActionsConfig.disabledActionIds.removeAll { $0 == "inspect_capture" }
        XCTAssertTrue(SettingsManager(defaults: defaults).quickActionsConfig.inspectionEnabled)
    }

    func testEmptyContextOffersOnlyInspectionAndDoesNotCopy() async throws {
        var config = QuickActionsConfig()
        config.disabledActionIds.removeAll { $0 == "inspect_capture" }
        let record = Self.record(text: "")
        let context = ActionContext(payload: .standardText(""), inspection: record)
        let actions = ActionRegistry.shared.actions(context: context, config: config)
        XCTAssertEqual(actions.map(\.id), ["inspect_capture"])
        let result = try await ActionExecutor().execute(XCTUnwrap(actions.first), context: context, config: config)
        guard case .inspectCapture(let returned, let currentText) = result else { return XCTFail("Expected presentation, never copy") }
        XCTAssertTrue(returned === record)
        XCTAssertEqual(currentText, "")
    }

    func testGeometryFlipsOriginAndHonorsAspectFitAndZoom() {
        let viewport = CGSize(width: 600, height: 400)
        let image = CGSize(width: 1000, height: 200)
        let rect = InspectionGeometry.imageRect(imageSize: image, viewport: viewport, zoom: 1)
        XCTAssertEqual(rect, CGRect(x: 0, y: 140, width: 600, height: 120))
        let box = InspectionGeometry.regionRect(CGRect(x: 0.1, y: 0.25, width: 0.3, height: 0.5), imageRect: rect)
        XCTAssertEqual(box, CGRect(x: 60, y: 170, width: 180, height: 60))
        let tall = InspectionGeometry.imageRect(imageSize: CGSize(width: 200, height: 1000), viewport: viewport, zoom: 2)
        XCTAssertEqual(tall, CGRect(x: 220, y: 0, width: 160, height: 800))
    }

    func testActualSizeKeepsPixelScaleAcrossResize() {
        let image = CGSize(width: 1000, height: 200)
        let small = InspectionGeometry.imageRect(imageSize: image, viewport: CGSize(width: 400, height: 300),
                                                zoom: 1, actualSize: true, displayScale: 2)
        let large = InspectionGeometry.imageRect(imageSize: image, viewport: CGSize(width: 800, height: 600),
                                                zoom: 1, actualSize: true, displayScale: 2)
        XCTAssertEqual(small.size, CGSize(width: 500, height: 100))
        XCTAssertEqual(large.size, small.size)
    }

    func testSelectionRevealCentersAndClampsToCanvasEdges() {
        let canvas = CGSize(width: 3000, height: 1000)
        let viewport = CGSize(width: 600, height: 400)
        XCTAssertEqual(InspectionGeometry.revealOrigin(regionRect: CGRect(x: 1100, y: 500, width: 200, height: 100),
                                                       canvasSize: canvas, viewport: viewport), CGPoint(x: 900, y: 350))
        XCTAssertEqual(InspectionGeometry.revealOrigin(regionRect: CGRect(x: 0, y: 0, width: 100, height: 40),
                                                       canvasSize: canvas, viewport: viewport), .zero)
        XCTAssertEqual(InspectionGeometry.revealOrigin(regionRect: CGRect(x: 2900, y: 960, width: 100, height: 40),
                                                       canvasSize: canvas, viewport: viewport), CGPoint(x: 2400, y: 600))
    }

    func testActualRecognitionRecordMatchesLegacyTextAndInput() async throws {
        let image = Self.image()
        let (result, record) = await withCheckedContinuation { continuation in
            OCRService.performOCRWithInspection(on: image) { continuation.resume(returning: ($0, $1)) }
        }
        guard case .success(let text) = result else { return XCTFail("Recognition failed") }
        XCTAssertTrue(record.original === image)
        XCTAssertEqual(record.input.width, image.width)
        XCTAssertEqual(record.input.height, image.height)
        XCTAssertEqual(record.assembledText, text)
        XCTAssertFalse(record.regions.isEmpty)
        XCTAssertEqual(record.regions.map(\.id), Array(1...record.regions.count))
        XCTAssertNil(record.errorDescription)
        let legacy = try await withCheckedThrowingContinuation { continuation in
            OCRService.performOCR(on: image) { result in
                switch result {
                case .success(let text): continuation.resume(returning: text)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        XCTAssertEqual(text, legacy)
    }

    func testBlankRecognitionStillHasImagesAndEmptyObservations() async {
        let image = Self.image(text: "")
        let (result, record) = await withCheckedContinuation { continuation in
            OCRService.performOCRWithInspection(on: image) { continuation.resume(returning: ($0, $1)) }
        }
        guard case .success(let text) = result else { return XCTFail("Blank image must succeed") }
        XCTAssertEqual(text, "")
        XCTAssertTrue(record.regions.isEmpty)
        XCTAssertTrue(record.original === image)
    }

    func testDisabledPipelineUsesLegacyRecognizerAndStaleInspectionsAreDiscarded() {
        var enabled = false
        var latest = UUID()
        var legacyCalls = 0
        var records: [OCRInspection] = []
        var pending: [@MainActor (Result<CaptureResult, Error>, OCRInspection) -> Void] = []
        var tokens: [RecognitionCancellation] = []
        let pipeline = CapturePipeline(isLatest: { $0 == latest }, cancellableRecognizers: [
            .standardOCR: { _, _, completion in
                legacyCalls += 1
                completion(.success(.standardText("Legacy")))
            }
        ], inspectingOCR: { _, token, completion in
            tokens.append(token)
            pending.append(completion)
        }, inspectionEnabled: { enabled }, deliverInspection: { _, _, record in records.append(record) },
           deliver: { _, _ in })
        let image = Self.image()
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: latest)
        XCTAssertEqual(legacyCalls, 1)
        XCTAssertTrue(pending.isEmpty)
        enabled = true
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: latest)
        latest = UUID()
        pipeline.completeCapture(image: image, screen: nil, mode: .standardOCR, requestID: latest)
        XCTAssertTrue(tokens[0].isCancelled)
        pending[0](.success(.standardText("Old")), Self.record(text: "Old"))
        let current = Self.record(text: "New")
        pending[1](.success(.standardText("New")), current)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records.first === current)
    }

    func testInspectedEmptyAndFailureAreDeliveredButCancellationIsNot() {
        let id = UUID()
        var pending: (@MainActor (Result<CaptureResult, Error>, OCRInspection) -> Void)?
        var deliveries: [String] = []
        let record = Self.record(text: "")
        let pipeline = CapturePipeline(isLatest: { $0 == id }, cancellableRecognizers: [
            .standardOCR: { _, _, _ in XCTFail("Inspection should use its own recognizer") }
        ], inspectingOCR: { _, _, completion in pending = completion }, inspectionEnabled: { true },
           deliverInspection: { outcome, _, delivered in
            XCTAssertTrue(delivered === record)
            switch outcome {
            case .noContent(.standardOCR): deliveries.append("empty")
            case .failed(.standardOCR, _): deliveries.append("failed")
            default: XCTFail("Unexpected inspected outcome")
            }
        }, deliver: { _, _ in XCTFail("Inspection must retain its record") })
        pipeline.completeCapture(image: Self.image(), screen: nil, mode: .standardOCR, requestID: id)
        pending?(.success(.standardText("")), record)
        pipeline.completeCapture(image: Self.image(), screen: nil, mode: .standardOCR, requestID: id)
        pending?(.failure(NSError(domain: "fixture", code: 1)), record)
        pipeline.completeCapture(image: Self.image(), screen: nil, mode: .standardOCR, requestID: id)
        pipeline.cancelRecognition()
        pending?(.success(.standardText("")), record)
        XCTAssertEqual(deliveries, ["empty", "failed"])
    }
}
