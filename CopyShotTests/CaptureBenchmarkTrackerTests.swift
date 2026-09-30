import Testing
@testable import CopyShot

#if DEBUG
struct CaptureBenchmarkTrackerTests {
    @Test func millisecondsIncludeWholeSeconds() {
        #expect(CaptureBenchmarkTracker.milliseconds(.milliseconds(1041)) == 1041)
        #expect(CaptureBenchmarkTracker.milliseconds(.milliseconds(3094)) == 3094)
        #expect(CaptureBenchmarkTracker.milliseconds(.milliseconds(94)) == 94)
    }
}
#endif
