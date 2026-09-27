import Testing
import Foundation
import CoreGraphics
@testable import CopyShot

@Suite("Capture request lifecycle")
struct CaptureRequestStateTests {
    @Test("A second request is rejected until the first finishes")
    func rejectsOverlappingRequests() throws {
        var state = CaptureRequestState()
        let firstResult = state.begin()
        let first = try #require(firstResult)
        let overlappingResult = state.begin()
        #expect(overlappingResult == nil)
        #expect(state.isCurrent(first))
        let finished = state.finish(first)
        #expect(finished)
        let nextResult = state.begin()
        #expect(nextResult != nil)
    }

    @Test("Late results from a canceled request cannot affect a new request")
    func rejectsStaleResults() throws {
        var state = CaptureRequestState()
        let firstResult = state.begin()
        let first = try #require(firstResult)
        let finished = state.finish(first)
        #expect(finished)
        let secondResult = state.begin()
        let second = try #require(secondResult)
        #expect(!state.isCurrent(first))
        let staleFinished = state.finish(first)
        #expect(!staleFinished)
        #expect(state.isCurrent(second))
    }

    @Test("Finishing image capture does not let older OCR results replace a newer request")
    func rejectsOlderOCRCompletion() throws {
        var state = CaptureRequestState()
        let firstResult = state.begin()
        let first = try #require(firstResult)
        _ = state.finish(first)
        #expect(state.isLatest(first))

        let secondResult = state.begin()
        let second = try #require(secondResult)
        #expect(!state.isLatest(first))
        #expect(state.isLatest(second))
    }
}

@Suite("Capture geometry")
@MainActor
struct CaptureGeometryTests {
    @Test("Selection coordinates stay local while output dimensions follow display scale")
    func scalesLocalSelection() {
        let rect = CGRect(x: 43, y: 27, width: 101.5, height: 30.5)
        let standard = ScreenCaptureManager.captureGeometry(for: rect, scaleFactor: 1)
        let retina = ScreenCaptureManager.captureGeometry(for: rect, scaleFactor: 2)

        #expect(standard.sourceRect == rect)
        #expect(retina.sourceRect == rect)
        #expect(standard.pixelWidth == 101)
        #expect(standard.pixelHeight == 30)
        #expect(retina.pixelWidth == 203)
        #expect(retina.pixelHeight == 61)
    }

    @Test("Tiny selections still request at least one pixel")
    func tinySelection() {
        let geometry = ScreenCaptureManager.captureGeometry(
            for: CGRect(x: 5, y: 6, width: 0.1, height: 0.1), scaleFactor: 2
        )
        #expect(geometry.pixelWidth == 1)
        #expect(geometry.pixelHeight == 1)
    }
}
