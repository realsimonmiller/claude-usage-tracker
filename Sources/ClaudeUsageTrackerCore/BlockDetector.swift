import Foundation

public struct UsageBlock: Sendable {
    /// Block start: timestamp of the first entry in this block, floored to the
    /// UTC hour (matches ccusage). End is exactly start + 5h.
    public let startedAt: Date
    public let endsAt: Date
    public let firstEntryAt: Date
    public let lastEntryAt: Date
    public let entries: [UsageEntry]

    public init(
        startedAt: Date,
        endsAt: Date,
        firstEntryAt: Date,
        lastEntryAt: Date,
        entries: [UsageEntry]
    ) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.firstEntryAt = firstEntryAt
        self.lastEntryAt = lastEntryAt
        self.entries = entries
    }

    /// Active iff (a) the user has been active within the session window and
    /// (b) we are still inside the block's nominal end time. Mirrors the
    /// `now - actualEndTime < session && now < endTime` check in ccusage.
    public func isActive(now: Date = Date()) -> Bool {
        let session: TimeInterval = 5 * 60 * 60
        return now.timeIntervalSince(lastEntryAt) < session && now < endsAt
    }

    public func remainingTime(now: Date = Date()) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    public var totals: UsageTotals {
        UsageAggregator.totals(for: entries)
    }
}

public enum BlockDetector {
    private static let sessionDuration: TimeInterval = 5 * 60 * 60

    /// Walk entries chronologically and group them into 5h blocks. A new block
    /// starts when (a) `entry.timestamp - currentBlockStart > 5h` or
    /// (b) `entry.timestamp - lastEntryTimestamp > 5h`. Block start is floored
    /// to the UTC hour. Output is in chronological order.
    public static func detectBlocks(from entries: [UsageEntry]) -> [UsageBlock] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        var blocks: [UsageBlock] = []
        var blockStart: Date = floorToHour(sorted[0].timestamp)
        var current: [UsageEntry] = [sorted[0]]
        var lastTimestamp: Date = sorted[0].timestamp

        for entry in sorted.dropFirst() {
            let timeSinceStart = entry.timestamp.timeIntervalSince(blockStart)
            let timeSinceLast = entry.timestamp.timeIntervalSince(lastTimestamp)

            if timeSinceStart > sessionDuration || timeSinceLast > sessionDuration {
                blocks.append(UsageBlock(
                    startedAt: blockStart,
                    endsAt: blockStart.addingTimeInterval(sessionDuration),
                    firstEntryAt: current.first!.timestamp,
                    lastEntryAt: lastTimestamp,
                    entries: current
                ))
                blockStart = floorToHour(entry.timestamp)
                current = [entry]
            } else {
                current.append(entry)
            }
            lastTimestamp = entry.timestamp
        }

        blocks.append(UsageBlock(
            startedAt: blockStart,
            endsAt: blockStart.addingTimeInterval(sessionDuration),
            firstEntryAt: current.first!.timestamp,
            lastEntryAt: lastTimestamp,
            entries: current
        ))

        return blocks
    }

    public static func activeBlock(from entries: [UsageEntry], now: Date = Date()) -> UsageBlock? {
        // The active block, if any, is the most recent one — earlier blocks
        // can't satisfy `now - lastEntry < 5h` because a later block would
        // have absorbed any nearby entries.
        detectBlocks(from: entries).last.flatMap { $0.isActive(now: now) ? $0 : nil }
    }

    private static var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    static func floorToHour(_ date: Date) -> Date {
        var components = utcCalendar.dateComponents(
            [.year, .month, .day, .hour], from: date
        )
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: components) ?? date
    }
}
