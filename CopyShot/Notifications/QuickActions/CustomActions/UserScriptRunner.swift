import Darwin
import Foundation

/// The injected task abstraction keeps tests out of the user's Application Scripts folder.
protocol ScriptTask: AnyObject {
    var standardInput: FileHandle? { get set }
    var standardOutput: FileHandle? { get set }
    var standardError: FileHandle? { get set }
    func launch(completion: @escaping @Sendable (Error?) -> Void) throws
}

extension NSUserUnixTask: ScriptTask {
    func launch(completion: @escaping @Sendable (Error?) -> Void) throws {
        execute(withArguments: [], completionHandler: completion)
    }
}

@MainActor
final class UserScriptRunner {
    static let shared = UserScriptRunner()
    private var invocations: [String: ScriptInvocation] = [:]
    private let makeTask: (URL) throws -> any ScriptTask
    var activeInvocationCount: Int { invocations.count }

    init(makeTask: @escaping (URL) throws -> any ScriptTask = { try NSUserUnixTask(url: $0) }) { self.makeTask = makeTask }

    func run(_ script: ScriptAction, input: String) async throws -> String {
        try Task.checkCancellation()
        guard input.utf8.count <= ScriptInvocation.textLimit else { throw CustomActionError.inputLimit }
        let id = script.metadata.id
        guard invocations.count < 4, invocations[id] == nil else { throw CustomActionError.busy }
        let invocation = ScriptInvocation(script: script, input: Data(input.utf8), makeTask: makeTask) { [weak self] in
            Task { @MainActor [weak self] in
                self?.invocations.removeValue(forKey: id)
            }
        }
        invocations[id] = invocation
        let bytes = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in invocation.start(continuation) }
        } onCancel: { invocation.cancel() }
        try Task.checkCancellation()
        guard let text = String(data: bytes, encoding: .utf8) else { throw CustomActionError.invalidOutput }
        return text
    }
}

/// All invocation state is confined to its serial queue. DispatchIO avoids blocked writer
/// threads and lets cancellation close streams without waiting for an uncooperative child.
private final class ScriptInvocation: @unchecked Sendable {
    static let textLimit = 4 * 1024 * 1024
    static let errorLimit = 64 * 1024
    private let script: ScriptAction
    private let input: Data
    private let makeTask: (URL) throws -> any ScriptTask
    private let onFinished: @Sendable () -> Void
    private let queue = DispatchQueue(label: "CopyShot.custom-actions.invocation", qos: .utility)
    private var task: (any ScriptTask)?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var channels: [DispatchIO] = []
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<Data, Error>?
    private var returnedResult: Result<Data, Error>?
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutEnded = false
    private var stderrEnded = false
    private var osCompleted = false
    private var osError: Error?
    private var launched = false
    private var released = false

    init(script: ScriptAction, input: Data, makeTask: @escaping (URL) throws -> any ScriptTask, onFinished: @escaping @Sendable () -> Void) {
        self.script = script
        self.input = input
        self.makeTask = makeTask
        self.onFinished = onFinished
    }

    func start(_ continuation: CheckedContinuation<Data, Error>) {
        queue.async { [self] in
            if let result = returnedResult { continuation.resume(with: result); releaseSlot(); return }
            self.continuation = continuation
            do {
                let values = try script.fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      FileManager.default.isExecutableFile(atPath: script.fileURL.path),
                      let source = try? String(contentsOf: script.fileURL, encoding: .utf8),
                      ScriptAction.digest(source) == script.revision else { throw CustomActionError.scriptChanged }
                let executable = try makeTask(script.fileURL)
                task = executable
                let inputPipe = Pipe(), outputPipe = Pipe(), errorPipe = Pipe()
                stdinPipe = inputPipe; stdoutPipe = outputPipe; stderrPipe = errorPipe
                executable.standardInput = inputPipe.fileHandleForReading
                executable.standardOutput = outputPipe.fileHandleForWriting
                executable.standardError = errorPipe.fileHandleForWriting
                let inputChannel = try channel(for: inputPipe.fileHandleForWriting)
                let outputChannel = try channel(for: outputPipe.fileHandleForReading)
                let errorChannel = try channel(for: errorPipe.fileHandleForReading)
                channels = [inputChannel, outputChannel, errorChannel]
                try inputPipe.fileHandleForWriting.close()
                try outputPipe.fileHandleForReading.close()
                try errorPipe.fileHandleForReading.close()
                read(outputChannel, isError: false)
                read(errorChannel, isError: true)
                try executable.launch { [self] error in queue.async { [self] in processCompleted(error) } }
                launched = true
                let timeoutTimer = DispatchSource.makeTimerSource(queue: queue)
                timer = timeoutTimer
                timeoutTimer.schedule(deadline: .now() + min(script.timeout, Double(Int.max / 1_000_000_000)))
                timeoutTimer.setEventHandler { [weak self] in self?.finish(.failure(CustomActionError.timedOut)) }
                timeoutTimer.resume()
                let data = input.withUnsafeBytes { DispatchData(bytes: $0) }
                inputChannel.write(offset: 0, data: data, queue: queue) { [self] done, _, error in
                    if done { inputChannel.close() }
                    if error != 0, error != EPIPE, error != ECANCELED, !osCompleted {
                        finish(.failure(CustomActionError.failed("Could not send script input: \(String(cString: strerror(error)))")))
                    }
                }
            } catch {
                finish(.failure(error))
                releaseSlot()
            }
        }
    }

    func cancel() { queue.async { [self] in finish(.failure(CancellationError())) } }

    private func channel(for handle: FileHandle) throws -> DispatchIO {
        let descriptor = dup(handle.fileDescriptor)
        guard descriptor >= 0 else { throw CustomActionError.failed("Could not open the script streams.") }
        // A child that stops reading must never send SIGPIPE to CopyShot itself.
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        let channel = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: queue) { _ in close(descriptor) }
        channel.setLimit(lowWater: 1)
        channel.setLimit(highWater: Self.errorLimit)
        return channel
    }

    private func read(_ channel: DispatchIO, isError: Bool) {
        channel.read(offset: 0, length: Int.max, queue: queue) { [self] done, data, error in
            if returnedResult == nil, let data {
                if isError {
                    let remaining = Self.errorLimit - stderr.count
                    if remaining > 0 { stderr.append(Data(data.prefix(remaining))) }
                } else if script.output != .none {
                    if data.count > Self.textLimit - stdout.count { finish(.failure(CustomActionError.outputLimit)) }
                    else { stdout.append(Data(data)) }
                }
            }
            if error != 0, error != ECANCELED, returnedResult == nil {
                finish(.failure(CustomActionError.failed("Could not read the script output: \(String(cString: strerror(error)))")))
            }
            if done {
                if isError { stderrEnded = true } else { stdoutEnded = true }
                completeIfReady()
            }
        }
    }

    private func processCompleted(_ error: Error?) {
        osCompleted = true
        osError = error
        // Keep the parent's child-facing handles until NSUserUnixTask has finished;
        // closing writers here yields EOF after the final output bytes are drained.
        try? stdoutPipe?.fileHandleForWriting.close()
        try? stderrPipe?.fileHandleForWriting.close()
        try? stdinPipe?.fileHandleForReading.close()
        channels.first?.close(flags: .stop)
        task = nil
        releaseSlot()
        completeIfReady()
    }

    private func completeIfReady() {
        guard osCompleted, stdoutEnded, stderrEnded, returnedResult == nil else { return }
        if let osError {
            let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            finish(.failure(CustomActionError.failed(message.isEmpty ? osError.localizedDescription : String(message.prefix(2048)))))
        } else { finish(.success(stdout)) }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard returnedResult == nil else { return }
        if case .failure(CustomActionError.timedOut) = result {
            DiagnosticLog.shared.record(.scriptTimedOut, action: .script)
        }
        returnedResult = result
        timer?.cancel(); timer = nil
        channels.forEach { $0.close(flags: .stop) }
        try? stdinPipe?.fileHandleForReading.close()
        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForWriting.close()
        try? stderrPipe?.fileHandleForWriting.close()
        continuation?.resume(with: result)
        continuation = nil
        stdout = Data(); stderr = Data()
        if !launched { releaseSlot() }
    }

    private func releaseSlot() {
        // A script identity stays occupied until this one-time release reaches the runner.
        guard !released else { return }
        released = true
        onFinished()
    }
}
