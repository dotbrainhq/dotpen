import Foundation

/// Watches one file. Editors and agents often save by writing a temp file and renaming it over the original,
/// which leaves the old descriptor pointing at a deleted file, so on delete or rename the observer reopens the path.
/// If the file stays gone past a short grace period, the observer stops polling and watches the parent folder
/// instead, so a deleted or moved file costs nothing until something appears at its path again.
public final class FileObserver: @unchecked Sendable {
    /// Reopen attempts before giving up on polling: 2 seconds at 0.2 seconds apart covers replace-style saves.
    static let retryLimit = 10

    private let url: URL
    private let debounce: Duration
    private let onChange: @Sendable () -> ()
    private let queue = DispatchQueue(label: "app.dotpen.file-observer")
    private var source: DispatchSourceFileSystemObject?
    private var folderSource: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    private var cancelled = false
    private var attemptCount = 0
    private var missingCount = 0

    /// How many times the observer has tried to open the file. Tests use it to check that retries stop.
    var openAttempts: Int { queue.sync { attemptCount } }

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
            folderSource?.cancel()
            folderSource = nil
        }
    }

    deinit {
        source?.cancel()
        folderSource?.cancel()
    }

    private func start() {
        guard !cancelled, source == nil else { return }
        attemptCount += 1
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            missingCount += 1
            if missingCount < Self.retryLimit {
                queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.start() }
            } else if folderSource == nil {
                waitForFile()
            }
            return
        }
        // The file came back after the observer gave up polling, so its contents changed while unwatched.
        let returned = missingCount >= Self.retryLimit
        missingCount = 0
        folderSource?.cancel()
        folderSource = nil

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
        if returned { scheduleNotify() }
    }

    /// Watches the parent folder for entries being added or renamed in, and reopens the file once it exists.
    /// If the folder itself goes away there is nothing left to watch, so the observer stays idle.
    private func waitForFile() {
        let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let folder = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        folder.setEventHandler { [weak self, weak folder] in
            guard let self, let folder else { return }
            if folder.data.contains(.delete) || folder.data.contains(.rename) {
                folder.cancel()
                self.folderSource = nil
                return
            }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.start()
            }
        }
        folder.setCancelHandler { close(descriptor) }
        folderSource = folder
        folder.resume()
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
