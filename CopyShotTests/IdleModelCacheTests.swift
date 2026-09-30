import XCTest
@testable import CopyShot

final class IdleModelCacheTests: XCTestCase {
    func testReusesModelUntilIdleThenReloads() throws {
        let queue = DispatchQueue(label: "CopyShot.Tests.ModelCache")
        var scheduled: [DispatchWorkItem] = []
        var loads = 0
        let cache = IdleModelCache<Int>(queue: queue, idleTimeout: 60, load: { loads += 1; return loads }, schedule: { delay, item in
            XCTAssertEqual(delay, 60)
            scheduled.append(item)
        })
        try queue.sync {
            XCTAssertEqual(try cache.value(), 1)
            cache.scheduleIdleRelease()
            XCTAssertEqual(try cache.value(), 1)
            cache.scheduleIdleRelease()
            scheduled[0].perform()
            XCTAssertTrue(cache.isLoaded) // A cancelled timer cannot unload renewed use.
            scheduled[1].perform()
            XCTAssertFalse(cache.isLoaded)
            XCTAssertEqual(try cache.value(), 2)
        }
    }

    func testPressureReleaseDiscardsModelAndOldIdleCallbackCannotDiscardReload() throws {
        let queue = DispatchQueue(label: "CopyShot.Tests.ModelPressure")
        var scheduled: [DispatchWorkItem] = []
        var loads = 0
        let cache = IdleModelCache<Int>(queue: queue, idleTimeout: 60, load: { loads += 1; return loads }, schedule: { _, item in scheduled.append(item) })
        try queue.sync {
            XCTAssertFalse(cache.isLoaded)
            XCTAssertEqual(try cache.value(), 1)
            cache.scheduleIdleRelease()
            cache.release()
            XCTAssertFalse(cache.isLoaded)
            XCTAssertEqual(try cache.value(), 2)
            scheduled[0].perform()
            XCTAssertTrue(cache.isLoaded)
            XCTAssertEqual(try cache.value(), 2)
        }
    }

    func testFailedLoadCanRetry() throws {
        let queue = DispatchQueue(label: "CopyShot.Tests.ModelRetry")
        var loads = 0
        let cache = IdleModelCache<Int>(queue: queue, idleTimeout: 60, load: {
            loads += 1
            if loads == 1 { throw NSError(domain: "Test", code: 1) }
            return loads
        })
        try queue.sync {
            XCTAssertThrowsError(try cache.value())
            XCTAssertFalse(cache.isLoaded)
            XCTAssertEqual(try cache.value(), 2)
        }
    }
}
