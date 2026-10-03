import Foundation
import Testing
@testable import CopyShot

@Suite("Recognition work scheduling")
struct RecognitionWorkTests {
    @Test("A cancelled queued job releases its captured resources without waiting for the worker")
    func cancelledJobReleasesResources() async {
        final class Resource {}
        let queue = DispatchQueue(label: "CopyShotTests.blockedWorker")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        let worker = RecognitionWorker(queue: queue)
        let cancellation = RecognitionCancellation()
        weak var released: Resource?
        do {
            let resource = Resource()
            released = resource
            worker.submit(cancellation: cancellation) { _ = resource }
        }
        #expect(released != nil)
        cancellation.cancel()
        #expect(released == nil)
        gate.signal()
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    @Test("Cancellation is idempotent and reaches handlers registered after cancellation")
    func cancellationHandlers() {
        let cancellation = RecognitionCancellation()
        var calls = 0
        cancellation.onCancel { calls += 1 }
        cancellation.cancel()
        cancellation.cancel()
        cancellation.onCancel { calls += 1 }
        #expect(calls == 2)
    }
}
