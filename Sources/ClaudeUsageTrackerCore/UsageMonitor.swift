import Foundation

public struct UsageSnapshot: Sendable {
    public let asOf: Date
    public let entryCount: Int
    /// The 5h block currently in flight — used for model/project breakdowns and
    /// block reset time fallback when sync data is absent.
    public let activeBlock: UsageBlock?
    /// The 7-day weekly window — used for weekly reset time fallback.
    public let activeWeek: WeeklyWindow?
    /// Live data pulled from claude.ai's own usage endpoint. All display
    /// percentages come from here; local NCU is only used for breakdowns.
    public let synced: SyncedUsage?

    public static let empty = UsageSnapshot(
        asOf: Date(),
        entryCount: 0,
        activeBlock: nil,
        activeWeek: nil,
        synced: nil
    )

    public init(
        asOf: Date,
        entryCount: Int,
        activeBlock: UsageBlock?,
        activeWeek: WeeklyWindow?,
        synced: SyncedUsage? = nil
    ) {
        self.asOf = asOf
        self.entryCount = entryCount
        self.activeBlock = activeBlock
        self.activeWeek = activeWeek
        self.synced = synced
    }

    public var displayPercent5h: Int { synced?.isFresh == true ? synced!.percent5h : 0 }
    public var displayPercent7d: Int { synced?.isFresh == true ? synced!.percent7d : 0 }
    public var displayDrivingPercent: Int { synced?.isFresh == true ? synced!.percent5h : 0 }

    public var displayBucket: HealthBucket {
        guard let s = synced, s.isFresh else { return .noData }
        return .from(percent: s.percent5h)
    }

    /// Reset time for the 5h block. Prefers synced value; falls back to local
    /// block detection so the countdown works even between polls.
    public var displayBlockResetAt: Date? {
        synced?.reset5hAt ?? activeBlock?.endsAt
    }

    /// Reset time for the weekly window. Prefers synced value; falls back to
    /// local window detection.
    public var displayWeekResetAt: Date? {
        synced?.reset7dAt ?? activeWeek?.endsAt
    }
}

/// Tails Claude Code's transcripts via FSEvents + a byte-offset incremental
/// scanner, then re-emits a `UsageSnapshot` whenever (a) new data arrives or
/// (b) the countdown timer ticks (so "resets in N" stays fresh even when
/// idle). All file I/O and aggregation runs on `workQueue`; the callback
/// fires on the main queue.
public final class UsageMonitor {
    public typealias Callback = (UsageSnapshot) -> Void

    private let tickInterval: TimeInterval
    private let root: URL
    private let workQueue = DispatchQueue(label: "cct.usage-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var watcher: FSEventsWatcher?
    private let scanner: IncrementalScanner
    private var latestSynced: SyncedUsage?
    private let onUpdate: Callback
    private var initialLoadComplete = false

    public init(
        root: URL = TranscriptScanner.defaultRoot,
        tickInterval: TimeInterval = 30,
        onUpdate: @escaping Callback
    ) {
        self.root = root
        self.tickInterval = tickInterval
        self.scanner = IncrementalScanner(root: root)
        self.onUpdate = onUpdate
    }

    public func start() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.scanner.loadInitial()
            self.initialLoadComplete = true
            self.emitSnapshot()
        }

        let watcher = FSEventsWatcher(paths: [root], latency: 1.0, queue: workQueue) { [weak self] paths in
            guard let self else { return }
            let jsonlPaths = paths.filter { $0.hasSuffix(".jsonl") }
            guard !jsonlPaths.isEmpty else { return }
            self.scanner.applyChanges(forPaths: jsonlPaths)
            if self.initialLoadComplete { self.emitSnapshot() }
        }
        watcher.start()
        self.watcher = watcher

        // Tick timer keeps the "resets in" countdown current — re-emits the
        // snapshot from in-memory entries (no file I/O).
        let t = DispatchSource.makeTimerSource(queue: workQueue)
        t.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        t.setEventHandler { [weak self] in
            guard let self, self.initialLoadComplete else { return }
            self.emitSnapshot()
        }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        watcher?.stop()
        watcher = nil
    }

    public func updateSynced(_ synced: SyncedUsage?) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.latestSynced = synced
            self.emitSnapshot()
        }
    }

    public func refreshNow() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.scanner.applyChanges(forPaths: nil)
            self.emitSnapshot()
        }
    }

    private func emitSnapshot() {
        let entries = scanner.currentEntries()
        let snapshot = Self.snapshot(from: entries, synced: latestSynced, now: Date())
        DispatchQueue.main.async { [onUpdate] in onUpdate(snapshot) }
    }

    public static func snapshot(
        from entries: [UsageEntry],
        synced: SyncedUsage? = nil,
        now: Date = Date()
    ) -> UsageSnapshot {
        let activeBlock = BlockDetector.activeBlock(from: entries, now: now)
        let activeWeek = WeeklyWindowDetector.activeWindow(from: entries, now: now)
        return UsageSnapshot(
            asOf: now,
            entryCount: entries.count,
            activeBlock: activeBlock,
            activeWeek: activeWeek,
            synced: synced
        )
    }
}
