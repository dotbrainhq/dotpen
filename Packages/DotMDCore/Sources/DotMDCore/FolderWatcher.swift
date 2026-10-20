import CoreServices
import Foundation

/// One changed path, with what FSEvents knows about it. Flags can be coalesced: a path created and then removed
/// within one batch reports both, so check the disk when the difference matters.
public struct FolderEvent: Sendable, Equatable {
    public let path: String
    public let isDirectory: Bool
    public let isRemoved: Bool
    public let isRenamed: Bool
    /// FSEvents dropped or merged events under this folder (MustScanSubDirs, UserDropped or KernelDropped).
    /// Anything below it may have changed.
    public let mustScanSubDirs: Bool

    public init(path: String, isDirectory: Bool, isRemoved: Bool, isRenamed: Bool, mustScanSubDirs: Bool = false) {
        self.path = path
        self.isDirectory = isDirectory
        self.isRemoved = isRemoved
        self.isRenamed = isRenamed
        self.mustScanSubDirs = mustScanSubDirs
    }
}

private let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                                 | kFSEventStreamEventFlagKernelDropped)

/// Reports changed paths under a folder through one FSEvents stream, batched by the stream's latency.
/// The owner keeps the watcher alive and calls cancel() when it stops watching.
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "app.dotmd.folder-watcher")
    private let queueKey = DispatchSpecificKey<Void>()
    private let onChange: @Sendable ([FolderEvent]) -> ()

    public init(url: URL, latency: TimeInterval = 0.15, onChange: @escaping @Sendable ([FolderEvent]) -> ()) {
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: ())
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self)
            let events: [FolderEvent] = (0..<count).compactMap { index in
                guard let path = list[index] as? String else { return nil }
                let flags = eventFlags[index]
                return FolderEvent(
                    path: path,
                    isDirectory: flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0,
                    isRemoved: flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0,
                    isRenamed: flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0,
                    mustScanSubDirs: flags & rescanFlags != 0
                )
            }
            watcher.onChange(events)
        }
        // WatchRoot reports an event for the root itself when it is moved or deleted.
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
                           | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Safe to call from any thread, including from inside onChange.
    public func cancel() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopStream()
        } else {
            queue.sync { stopStream() }
        }
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        cancel()
    }
}
