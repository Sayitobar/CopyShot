import Foundation

/// All access and eviction run on the recognizer's serial queue; active inference never loses its model.
final class IdleModelCache<Model> {
    private let queue: DispatchQueue
    private var policy: ModelUnloadPolicy
    private let load: () throws -> Model
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var model: Model?
    private var eviction: DispatchWorkItem?
    private var generation = UUID()

    var isLoaded: Bool { model != nil }
    var currentPolicy: ModelUnloadPolicy { policy }

    init(queue: DispatchQueue, policy: ModelUnloadPolicy = .defaultTimeout, load: @escaping () throws -> Model,
         schedule: ((TimeInterval, DispatchWorkItem) -> Void)? = nil) {
        self.queue = queue
        self.policy = policy
        self.load = load
        self.schedule = schedule ?? { delay, item in queue.asyncAfter(deadline: .now() + delay, execute: item) }
    }

    /// Convenience initializer maintaining backwards compatibility with timeout-based callers (e.g. tests).
    convenience init(queue: DispatchQueue, idleTimeout: TimeInterval, load: @escaping () throws -> Model,
                     schedule: ((TimeInterval, DispatchWorkItem) -> Void)? = nil) {
        self.init(queue: queue, policy: ModelUnloadPolicy(rawSeconds: idleTimeout), load: load, schedule: schedule)
    }

    func updatePolicy(_ newPolicy: ModelUnloadPolicy) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.policy = newPolicy
        if isLoaded {
            if newPolicy.isImmediately {
                release()
            } else if newPolicy.isNever {
                cancelEviction()
            } else if let timeout = newPolicy.timeout, timeout > 0 {
                scheduleIdleRelease()
            }
        }
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

        if policy.isImmediately {
            release()
            return
        }
        if policy.isNever {
            return
        }
        guard let timeout = policy.timeout, timeout > 0 else {
            release()
            return
        }

        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.release()
        }
        eviction = item
        schedule(timeout, item)
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
