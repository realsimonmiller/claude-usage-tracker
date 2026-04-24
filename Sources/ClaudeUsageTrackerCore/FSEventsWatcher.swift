import CoreServices
import Foundation

/// Thin Swift wrapper around FSEvents. Coalesces filesystem events under
/// `paths` (recursive) and fires a callback with the unique set of changed
/// file paths. Callback runs on the configured dispatch queue.
public final class FSEventsWatcher {
    public typealias Callback = (Set<String>) -> Void

    private let watchPaths: [String]
    private let latency: TimeInterval
    private let callback: Callback
    private let queue: DispatchQueue
    private var stream: FSEventStreamRef?

    public init(
        paths: [URL],
        latency: TimeInterval = 1.0,
        queue: DispatchQueue = DispatchQueue.global(qos: .utility),
        callback: @escaping Callback
    ) {
        self.watchPaths = paths.map { $0.path }
        self.latency = latency
        self.queue = queue
        self.callback = callback
    }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // UseCFTypes promotes `eventPaths` from a raw C-string array to a
        // CFArrayRef of CFStrings, which Swift can toll-free bridge to
        // `[String]`. Without it, the bridge segfaults.
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
        )

        let rawCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let nsArray = unsafeBitCast(eventPaths, to: NSArray.self)
            guard let paths = nsArray as? [String] else { return }
            let changed = Set(paths)
            if !changed.isEmpty {
                watcher.callback(changed)
            }
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            rawCallback,
            &context,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
