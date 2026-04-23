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

/// Polls the transcript directory on a timer, recomputes usage totals against
/// the configured plan caps, and pushes a `UsageSnapshot` to its callback on
/// the main thread. M3 uses a brute-force re-scan; M4 will swap in FSEvents +
/// incremental tailing.
public final class UsageMonitor {
    public typealias Callback = (UsageSnapshot) -> Void

    private let pollInterval: TimeInterval
    private let workQueue = DispatchQueue(label: "cct.usage-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var plan: PlanTier
    private let onUpdate: Callback

    public init(plan: PlanTier, pollInterval: TimeInterval = 30, onUpdate: @escaping Callback) {
        self.plan = plan
        self.pollInterval = pollInterval
        self.onUpdate = onUpdate
    }

    public func start() {
        scanOnce()
        let t = DispatchSource.makeTimerSource(queue: workQueue)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.scanOnce() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func setPlan(_ newPlan: PlanTier) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.plan = newPlan
            self.scanOnce()
        }
    }

    public func refreshNow() {
        workQueue.async { [weak self] in self?.scanOnce() }
    }

    private func scanOnce() {
        let now = Date()
        let entries = TranscriptScanner.loadAllEntries()
        let snapshot = Self.snapshot(from: entries, plan: plan, now: now)
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
        let driving = max(pct5h, pct7d)
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
