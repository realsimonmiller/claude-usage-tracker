import Foundation

public struct UsageSnapshot: Sendable {
    public let plan: PlanTier
    public let totals5h: UsageTotals
    public let totals7d: UsageTotals
    public let percent5h: Int
    public let percent7d: Int
    public let drivingPercent: Int
    public let bucket: HealthBucket
    public let asOf: Date
    public let entryCount: Int
    /// The 5h block currently in flight, if any. `nil` when the user has been
    /// idle for >5h (in which case `totals5h` is `.zero`).
    public let activeBlock: UsageBlock?

    public static let empty = UsageSnapshot(
        plan: .pro,
        totals5h: .zero,
        totals7d: .zero,
        percent5h: 0,
        percent7d: 0,
        drivingPercent: 0,
        bucket: .noData,
        asOf: Date(),
        entryCount: 0,
        activeBlock: nil
    )

    public init(
        plan: PlanTier,
        totals5h: UsageTotals,
        totals7d: UsageTotals,
        percent5h: Int,
        percent7d: Int,
        drivingPercent: Int,
        bucket: HealthBucket,
        asOf: Date,
        entryCount: Int,
        activeBlock: UsageBlock?
    ) {
        self.plan = plan
        self.totals5h = totals5h
        self.totals7d = totals7d
        self.percent5h = percent5h
        self.percent7d = percent7d
        self.drivingPercent = drivingPercent
        self.bucket = bucket
        self.asOf = asOf
        self.entryCount = entryCount
        self.activeBlock = activeBlock
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
    private var plan: PlanTier
    private let onUpdate: Callback
    private var initialLoadComplete = false

    public init(
        plan: PlanTier,
        root: URL = TranscriptScanner.defaultRoot,
        tickInterval: TimeInterval = 30,
        onUpdate: @escaping Callback
    ) {
        self.plan = plan
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
            // Filter to .jsonl paths so we don't re-scan on every dir touch.
            let jsonlPaths = paths.filter { $0.hasSuffix(".jsonl") }
            guard !jsonlPaths.isEmpty else { return }
            self.scanner.applyChanges(forPaths: jsonlPaths)
            if self.initialLoadComplete {
                self.emitSnapshot()
            }
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

    public func setPlan(_ newPlan: PlanTier) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.plan = newPlan
            self.emitSnapshot()
        }
    }

    public func refreshNow() {
        workQueue.async { [weak self] in
            guard let self else { return }
            // Force a directory rediscovery in case FSEvents missed something.
            self.scanner.applyChanges(forPaths: nil)
            self.emitSnapshot()
        }
    }

    private func emitSnapshot() {
        let entries = scanner.currentEntries()
        let snapshot = Self.snapshot(from: entries, plan: plan, now: Date())
        DispatchQueue.main.async { [onUpdate] in
            onUpdate(snapshot)
        }
    }

    public static func snapshot(from entries: [UsageEntry], plan: PlanTier, now: Date = Date()) -> UsageSnapshot {
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60

        let activeBlock = BlockDetector.activeBlock(from: entries, now: now)
        let totals5h = activeBlock?.totals ?? .zero
        let totals7d = UsageAggregator.totals(for: entries, in: sevenDays, now: now)

        let cap5h = plan.cap5h
        let cap7d = plan.cap7d
        let pct5h = cap5h > 0 ? Int((totals5h.ncu / cap5h) * 100) : 0
        let pct7d = cap7d > 0 ? Int((totals7d.ncu / cap7d) * 100) : 0
        // The collapsed menu bar (face + %) is driven by the 5h block only —
        // it's the cap users actually feel from minute to minute. 7d is shown
        // in the expanded menu for context.
        let driving = pct5h
        let bucket: HealthBucket = entries.isEmpty ? .noData : .from(percent: driving)

        return UsageSnapshot(
            plan: plan,
            totals5h: totals5h,
            totals7d: totals7d,
            percent5h: pct5h,
            percent7d: pct7d,
            drivingPercent: driving,
            bucket: bucket,
            asOf: now,
            entryCount: entries.count,
            activeBlock: activeBlock
        )
    }
}
