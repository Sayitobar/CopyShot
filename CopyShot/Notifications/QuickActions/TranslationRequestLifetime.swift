import Foundation

/// Owns completion through session startup, language preparation, and translation.
/// Every terminal path completes once; late framework callbacks cannot finish a newer request.
@MainActor
final class TranslationRequestLifetime {
    private struct Request {
        let id: UUID
        let cancelOperation: () -> Void
        let completion: (Result<TranslationResult, Error>) -> Void
    }
    private var request: Request?
    private var deadline: Task<Void, Never>?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 120) { self.timeout = timeout }

    func start(id: UUID, cancelOperation: @escaping () -> Void,
               completion: @escaping (Result<TranslationResult, Error>) -> Void) {
        if let previous = request { cancel(id: previous.id) }
        request = Request(id: id, cancelOperation: cancelOperation, completion: completion)
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
            catch { return }
            let error = NSError(domain: "CopyShot.Translation", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Translation timed out. Complete any Apple language-download prompt, check your connection if a language pack is needed, then retry."
            ])
            self?.finish(id: id, result: .failure(error))
        }
    }

    func isCurrent(_ id: UUID) -> Bool { request?.id == id }
    func cancel(id: UUID) { finish(id: id, result: .failure(CancellationError())) }

    func finish(id: UUID, result: Result<TranslationResult, Error>) {
        guard let request, request.id == id else { return }
        self.request = nil
        if case .failure(let error) = result, (error as NSError).domain == "CopyShot.Translation", (error as NSError).code == -3 {
            DiagnosticLog.shared.record(.translationTimedOut, action: .translation, error: error)
        }
        deadline?.cancel()
        deadline = nil
        request.cancelOperation()
        request.completion(result)
    }
}
