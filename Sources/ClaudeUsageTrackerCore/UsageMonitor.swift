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
    /// The 7-day weekly window currently in flight. `nil` if the user hasn't
    /// messaged within the past 7 days.
    public let activeWeek: WeeklyWindow?
    /// Live data pulled from claude.ai's own usage endpoint, if a recent sync
    /// succeeded. When set, the `display*` accessors return these values
    /// instead of our local approximations.
    public let synced: SyncedUsage?

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
        activeBlock: nil,
        activeWeek: nil,
        synced: nil
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
        activeBlock: UsageBlock?,
        activeWeek: WeeklyWindow?,
        synced: SyncedUsage? = nil
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
        self.activeWeek = activeWeek
        self.synced = synced
    }

    /// 5h percent to show: prefers live claude.ai data when fresh.
    public var displayPercent5h: Int {
        if let s = synced, s.isFresh { return s.percent5h }
        return percent5h
    }
    public var displayPercent7d: Int {
        if let s = synced, s.isFresh { return s.percent7d }
        return percent7d
    }
    public var displayDrivingPercent: Int {
        if let s = synced, s.isFresh { return s.percent5h }
        return drivingPercent
    }
    public var displayBlockResetAt: Date? {
        if let r = synced?.reset5hAt, let s = synced, s.isFresh { return r }
        return activeBlock?.endsAt
    }
    public var displayWeekResetAt: Date? {
        if let r = synced?.reset7dAt, let s = synced, s.isFresh { return r }
        return activeWeek?.endsAt
    }
    public var displayBucket: HealthBucket {
        if synced?.isFresh == true { return .from(percent: displayPercent5h) }
        return bucket
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
    /// User-supplied weekly anchor. When set, it's the next claude.ai-reported
    /// reset moment; we render the weekly window as `[anchor - 7d, anchor)`
    /// instead of using auto-detection.
    private var weeklyResetOverride: Date?
    private var latestSynced: SyncedUsage?
    private let onUpdate: Callback
    private var initialLoadComplete = false

    public init(
        plan: PlanTier,
        weeklyResetOverride: Date? = nil,
        root: URL = TranscriptScanner.defaultRoot,
        tickInterval: TimeInterval = 30,
        onUpdate: @escaping Callback
    ) {
        self.plan = plan
        self.weeklyResetOverride = weeklyResetOverride
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

    public func setWeeklyResetOverride(_ next: Date?) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.weeklyResetOverride = next
            self.emitSnapshot()
        }
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
            // Force a directory rediscovery in case FSEvents missed something.
            self.scanner.applyChanges(forPaths: nil)
            self.emitSnapshot()
        }
    }

    private func emitSnapshot() {
        let entries = scanner.currentEntries()
        let snapshot = Self.snapshot(
            from: entries,
            plan: plan,
            weeklyResetOverride: weeklyResetOverride,
            synced: latestSynced,
            now: Date()
        )
        DispatchQueue.main.async { [onUpdate] in
            onUpdate(snapshot)
        }
    }

    public static func snapshot(
        from entries: [UsageEntry],
        plan: PlanTier,
        weeklyResetOverride: Date? = nil,
        synced: SyncedUsage? = nil,
        now: Date = Date()
    ) -> UsageSnapshot {
        let activeBlock = BlockDetector.activeBlock(from: entries, now: now)
        let activeWeek: WeeklyWindow?
        if let nextReset = weeklyResetOverride, nextReset > now {
            // User pinned the next reset (from claude.ai). Anchor a window to it.
            activeWeek = WeeklyWindowDetector.windowAnchored(
                endingAt: nextReset, from: entries, now: now
            )
        } else {
            // Auto-detect from message history. Approximate; may differ from
            // Anthropic's actual alignment (see DESIGN.md §8).
            activeWeek = WeeklyWindowDetector.activeWindow(from: entries, now: now)
        }
        let totals5h = activeBlock?.totals ?? .zero
        let totals7d = activeWeek?.totals ?? .zero

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
            activeBlock: activeBlock,
            activeWeek: activeWeek,
            synced: synced
        )
    }
}
