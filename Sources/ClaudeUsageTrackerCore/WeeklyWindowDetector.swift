import Foundation

public struct WeeklyWindow: Sendable {
    /// Window start: timestamp of the first message in this window. Unlike
    /// `UsageBlock`, weekly windows are NOT floored — Anthropic anchors the
    /// week to your actual first-message timestamp.
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

    /// Weekly windows don't have an idle-gap rule like 5h blocks; they're
    /// active until the 7-day duration elapses.
    public func isActive(now: Date = Date()) -> Bool {
        now < endsAt
    }

    public func remainingTime(now: Date = Date()) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    public var totals: UsageTotals {
        UsageAggregator.totals(for: entries)
    }
}

/// Anthropic's "All models" weekly cap on Pro/Max plans starts on the first
/// message after the previous weekly window expired and runs exactly 7 days.
/// See `docs/DESIGN.md` §8 for the source observations.
public enum WeeklyWindowDetector {
    private static let windowDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Walk entries chronologically, opening a new window every time an entry
    /// lands more than 7 days after the current window's start. No
    /// idle-gap rule — Anthropic doesn't reset the week mid-cycle just
    /// because you went quiet.
    public static func detectWindows(from entries: [UsageEntry]) -> [WeeklyWindow] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        var windows: [WeeklyWindow] = []
        var windowStart: Date = sorted[0].timestamp
        var current: [UsageEntry] = [sorted[0]]
        var lastTimestamp: Date = sorted[0].timestamp

        for entry in sorted.dropFirst() {
            let timeSinceStart = entry.timestamp.timeIntervalSince(windowStart)
            if timeSinceStart > windowDuration {
                windows.append(WeeklyWindow(
                    startedAt: windowStart,
                    endsAt: windowStart.addingTimeInterval(windowDuration),
                    firstEntryAt: current.first!.timestamp,
                    lastEntryAt: lastTimestamp,
                    entries: current
                ))
                windowStart = entry.timestamp
                current = [entry]
            } else {
                current.append(entry)
            }
            lastTimestamp = entry.timestamp
        }

        windows.append(WeeklyWindow(
            startedAt: windowStart,
            endsAt: windowStart.addingTimeInterval(windowDuration),
            firstEntryAt: current.first!.timestamp,
            lastEntryAt: lastTimestamp,
            entries: current
        ))

        return windows
    }

    public static func activeWindow(from entries: [UsageEntry], now: Date = Date()) -> WeeklyWindow? {
        detectWindows(from: entries).last.flatMap { $0.isActive(now: now) ? $0 : nil }
    }

    /// Build a weekly window that ends exactly at `nextReset` (the user's
    /// claude.ai-reported reset time). Lets us mirror Anthropic's actual
    /// alignment when our auto-detected anchor has drifted out of sync.
    public static func windowAnchored(
        endingAt nextReset: Date,
        from entries: [UsageEntry],
        now: Date = Date()
    ) -> WeeklyWindow {
        let start = nextReset.addingTimeInterval(-windowDuration)
        let inRange = entries
            .filter { $0.timestamp >= start && $0.timestamp < nextReset }
            .sorted { $0.timestamp < $1.timestamp }
        return WeeklyWindow(
            startedAt: start,
            endsAt: nextReset,
            firstEntryAt: inRange.first?.timestamp ?? start,
            lastEntryAt: inRange.last?.timestamp ?? start,
            entries: inRange
        )
    }
}
