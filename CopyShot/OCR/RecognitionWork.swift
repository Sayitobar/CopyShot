import Foundation

/// Cancellation removes queued image owners and cooperatively stops active recognition.
/// Cancelled work does not deliver a result to its caller.
final class RecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }

    func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
        } else {
            handlers.append(handler)
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let callbacks = handlers
        handlers.removeAll()
        lock.unlock()
        callbacks.forEach { $0() }
    }
}

/// Only the drain is submitted to GCD, so cancelled pending closures release their images immediately.
final class RecognitionWorker: @unchecked Sendable {
    private struct Job {
        let cancellation: RecognitionCancellation
        let work: () -> Void
    }

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var jobs: [Job] = []
    private var isDraining = false

    init(queue: DispatchQueue) { self.queue = queue }

    func submit(cancellation: RecognitionCancellation, work: @escaping () -> Void) {
        lock.lock()
        guard !cancellation.isCancelled else { lock.unlock(); return }
        jobs.append(Job(cancellation: cancellation, work: work))
        let startDrain = !isDraining
        isDraining = true
        lock.unlock()
        cancellation.onCancel { [weak self, weak cancellation] in
            guard let self, let cancellation else { return }
            self.lock.lock()
            self.jobs.removeAll { $0.cancellation === cancellation }
            self.lock.unlock()
        }
        if startDrain {
            queue.async { [self] in
                while let job = nextJob() {
                    if !job.cancellation.isCancelled {
                        autoreleasepool { job.work() }
                    }
                }
            }
        }
    }

    private func nextJob() -> Job? {
        lock.lock()
        defer { lock.unlock() }
        guard !jobs.isEmpty else { isDraining = false; return nil }
        return jobs.removeFirst()
    }
}

/// Shares one in-flight warm-up and its success/failure with every interested capture session.
final class PrewarmCoalescer<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [Key: [(Bool) -> Void]] = [:]

    func run(key: Key, start: (@escaping (Bool) -> Void) -> Void,
             completion: @escaping (Bool) -> Void = { _ in }) {
        lock.lock()
        if completions[key] != nil {
            completions[key]?.append(completion)
            lock.unlock()
            return
        }
        completions[key] = [completion]
        lock.unlock()
        start { [self] success in
            lock.lock()
            let callbacks = completions.removeValue(forKey: key) ?? []
            lock.unlock()
            callbacks.forEach { $0(success) }
        }
    }
}
