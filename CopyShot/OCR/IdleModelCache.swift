import Foundation

/// All access and eviction run on the recognizer's serial queue; active inference never loses its model.
final class IdleModelCache<Model> {
    private let queue: DispatchQueue
    private let idleTimeout: TimeInterval
    private let load: () throws -> Model
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var model: Model?
    private var eviction: DispatchWorkItem?
    private var generation = UUID()

    var isLoaded: Bool { model != nil }

    init(queue: DispatchQueue, idleTimeout: TimeInterval, load: @escaping () throws -> Model,
         schedule: ((TimeInterval, DispatchWorkItem) -> Void)? = nil) {
        precondition(idleTimeout >= 0 && idleTimeout.isFinite)
        self.queue = queue
        self.idleTimeout = idleTimeout
        self.load = load
        self.schedule = schedule ?? { delay, item in queue.asyncAfter(deadline: .now() + delay, execute: item) }
    }

    func value() throws -> Model {
        dispatchPrecondition(condition: .onQueue(queue))
        cancelEviction()
        if let model { return model }
        let loaded = try load()
        model = loaded
        return loaded
    }

    func scheduleIdleRelease() {
        dispatchPrecondition(condition: .onQueue(queue))
        cancelEviction()
        guard model != nil else { return }
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.release()
        }
        eviction = item
        schedule(idleTimeout, item)
    }

    func release() {
        dispatchPrecondition(condition: .onQueue(queue))
        cancelEviction()
        model = nil
    }

    private func cancelEviction() {
        eviction?.cancel()
        eviction = nil
        generation = UUID()
    }
}
