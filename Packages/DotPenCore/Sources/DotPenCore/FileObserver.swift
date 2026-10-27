import Foundation

/// Watches one file. Editors and agents often save by writing a temp file and renaming it over the original,
/// which leaves the old descriptor pointing at a deleted file, so on delete or rename the observer reopens the path.
public final class FileObserver: @unchecked Sendable {
    private let url: URL
    private let debounce: Duration
    private let onChange: @Sendable () -> ()
    private let queue = DispatchQueue(label: "app.dotpen.file-observer")
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    private var cancelled = false

    public init(url: URL, debounce: Duration = .milliseconds(100), onChange: @escaping @Sendable () -> ()) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
        queue.async { self.start() }
    }

    public func cancel() {
        queue.sync {
            cancelled = true
            pendingNotify?.cancel()
            source?.cancel()
            source = nil
        }
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        guard !cancelled else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.start() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                source.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.start() }
            }
            self.scheduleNotify()
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func scheduleNotify() {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled else { return }
            self.onChange()
        }
        pendingNotify = work
        let parts = debounce.components
        let delay = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
