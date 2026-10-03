import AppKit
import Observation
import Testing
@testable import CopyShot

private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

@Suite("Optimization state", .serialized)
@MainActor
struct OptimizationStateTests {
    @Test("Shelf heights are reused until content or layout settings change")
    func shelfMeasurementReuse() {
        var measurements = 0
        let cache = ShelfLayout.Measurements { actions, _ in
            measurements += 1
            return CGFloat(actions.count * 38)
        }
        let child = QuickAction(id: "child", title: "Child", icon: .system("star"), shortcutNumber: 1)
        let menu = QuickAction(id: "parent", title: "Parent", icon: .system("star"), shortcutNumber: 1,
                               subActions: [child])
        #expect(cache.prepare(actions: [menu]).main == 38)
        #expect(cache.submenuHeight(for: menu) == 38)
        #expect(cache.submenuHeight(for: menu) == 38)
        _ = cache.prepare(actions: [menu])
        #expect(measurements == 2)
        let longer = QuickAction(id: "child2", title: "Changed", icon: .system("star"), shortcutNumber: 2)
        let changed = QuickAction(id: "parent", title: "Parent", icon: .system("star"), shortcutNumber: 1,
                                  subActions: [child, longer])
        #expect(cache.prepare(actions: [changed]).submenu == 76)
        #expect(measurements == 3)
        cache.invalidate()
        _ = cache.prepare(actions: [changed])
        #expect(measurements == 5)
        let settings = SettingsManager.shared
        let numeric = settings.quickActionsConfig.showNumericShortcuts
        let appearance = settings.appearance
        let debug = settings.showDebugOverlay
        defer {
            settings.quickActionsConfig.showNumericShortcuts = numeric
            settings.appearance = appearance
            settings.showDebugOverlay = debug
        }
        settings.quickActionsConfig.showNumericShortcuts.toggle()
        _ = cache.prepare(actions: [changed])
        #expect(measurements == 7)
        settings.appearance = appearance == .dark ? .light : .dark
        _ = cache.prepare(actions: [changed])
        #expect(measurements == 9)
        settings.showDebugOverlay.toggle()
        _ = cache.prepare(actions: [changed])
        #expect(measurements == 11)
    }

    @Test("Unrelated settings changes do not invalidate debug decoration")
    func narrowDebugObservation() throws {
        let suite = "CopyShotTests.debugObservation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        let invalidations = ObservationCounter()
        withObservationTracking {
            _ = settings.debugOverlay.isEnabled
        } onChange: {
            invalidations.increment()
        }
        settings.recordCaptureModeUsed(.table)
        #expect(invalidations.value == 0)
        settings.showDebugOverlay = true
        #expect(invalidations.value == 1)
    }

    @Test("Prewarm coalescing shares completion and permits retry after failure")
    func coalescedPrewarmRetry() {
        let coalescer = PrewarmCoalescer<String>()
        var starts = 0
        var finish: ((Bool) -> Void)?
        var results: [Bool] = []
        for _ in 0..<2 {
            coalescer.run(key: "OCR", start: { done in starts += 1; finish = done },
                          completion: { results.append($0) })
        }
        #expect(starts == 1)
        finish?(false)
        #expect(results == [false, false])
        coalescer.run(key: "OCR", start: { done in starts += 1; done(true) },
                      completion: { results.append($0) })
        #expect(starts == 2)
        #expect(results == [false, false, true])
    }
}
