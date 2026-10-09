import Darwin
import Foundation

/// Directory events detect additions/replacements; file events detect edits to existing inodes.
final class ScriptDirectoryWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CopyShot.custom-actions.watcher", qos: .utility)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let changed: @Sendable () -> Void

    init(changed: @escaping @Sendable () -> Void) { self.changed = changed }

    func watch(directory: URL, files: [URL]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sources.forEach { $0.cancel() }
            self.sources = []
            // Watch the parent as well so a deleted/recreated scripts directory can recover.
            let urls = Array(Set([directory, directory.deletingLastPathComponent()] + files))
            for url in urls {
                let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
                guard descriptor >= 0 else { continue }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .attrib, .extend, .revoke], queue: self.queue)
                source.setEventHandler { [weak self] in self?.scheduleChange() }
                source.setCancelHandler { close(descriptor) }
                self.sources.append(source)
                source.resume()
            }
        }
    }

    private func scheduleChange() {
        pending?.cancel()
        let changed = changed
        let work = DispatchWorkItem { changed() }
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
    }

    deinit {
        pending?.cancel()
        sources.forEach { $0.cancel() }
    }
}
