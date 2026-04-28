import SwiftUI
import ClaudeUsageTrackerCore

struct PopoverView: View {
    let snapshot: UsageSnapshot
    let weeklyOverrideActive: Bool
    let onRefresh: () -> Void
    let onQuit: () -> Void

    /// Drives live countdown updates while the popover is open.
    @State private var tickNow: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            blockSection
            weeklySection
            if !modelBreakdown.isEmpty {
                Divider()
                modelSection
            }
            if !projectBreakdown.isEmpty {
                Divider()
                projectsSection
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .onReceive(ticker) { now in tickNow = now }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: MascotRenderer.image(percentUsed: snapshot.drivingPercent, pointSize: 44))
                .interpolation(.none)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code Usage")
                    .font(.system(size: 14, weight: .semibold))
                Text(snapshot.plan.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var blockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("5-HOUR BLOCK")
            ProgressBar(percent: snapshot.percent5h)
            HStack(spacing: 8) {
                Text(formatNCU(snapshot.totals5h.ncu) + " / " + formatNCU(snapshot.plan.cap5h) + " NCU")
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Text(blockResetText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionLabel("WEEKLY WINDOW")
                Text(weeklyOverrideActive ? "calibrated" : "auto")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            }
            ProgressBar(percent: snapshot.percent7d)
            HStack(spacing: 8) {
                Text(formatNCU(snapshot.totals7d.ncu) + " / " + formatNCU(snapshot.plan.cap7d) + " NCU")
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Text(weeklyResetText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("CURRENT BLOCK BY MODEL")
            ForEach(modelBreakdown, id: \.0) { (label, ncu, share) in
                BreakdownRow(label: label, value: formatNCU(ncu) + " NCU", share: share)
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("TOP PROJECTS, CURRENT BLOCK")
            ForEach(projectBreakdown, id: \.0) { (label, ncu, share) in
                BreakdownRow(label: label, value: formatNCU(ncu) + " NCU", share: share)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { onRefresh() }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: [.command])
            Spacer()
            Text("Updated \(formatTimeAgo(snapshot.asOf, now: tickNow))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: [.command])
        }
        .font(.system(size: 11))
    }

    // MARK: - Derived

    private var blockResetText: String {
        guard let block = snapshot.activeBlock else { return "no active block" }
        return "resets in " + formatRemaining(block.remainingTime(now: tickNow))
    }

    private var weeklyResetText: String {
        guard let week = snapshot.activeWeek else { return "no active week" }
        return "resets in " + formatRemaining(week.remainingTime(now: tickNow))
    }

    private var modelBreakdown: [(String, Double, Double)] {
        guard let block = snapshot.activeBlock else { return [] }
        var byFamily: [ModelFamily: Double] = [:]
        for entry in block.entries {
            byFamily[ModelFamily.from(model: entry.model), default: 0] += entry.ncu
        }
        let total = byFamily.values.reduce(0, +)
        guard total > 0 else { return [] }
        let order: [ModelFamily] = [.opus, .sonnet, .haiku, .unknown]
        return order.compactMap { family in
            guard let ncu = byFamily[family], ncu > 0 else { return nil }
            return (family.rawValue.capitalized, ncu, ncu / total)
        }
    }

    private var projectBreakdown: [(String, Double, Double)] {
        guard let block = snapshot.activeBlock else { return [] }
        var byCwd: [String: Double] = [:]
        for entry in block.entries {
            let key = projectName(from: entry.cwd) ?? "unknown"
            byCwd[key, default: 0] += entry.ncu
        }
        let total = byCwd.values.reduce(0, +)
        guard total > 0 else { return [] }
        return byCwd
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { ($0.key, $0.value, $0.value / total) }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

// MARK: - Subcomponents

private struct ProgressBar: View {
    let percent: Int

    private static let cellCount = 20

    var body: some View {
        let filled = max(0, min(Self.cellCount, Int((Double(percent) / 100.0) * Double(Self.cellCount).rounded())))
        HStack(spacing: 2) {
            ForEach(0..<Self.cellCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < filled ? barColor : Color.secondary.opacity(0.18))
                    .frame(height: 10)
            }
            Text("\(percent)%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var barColor: Color {
        switch percent {
        case ..<50: return .green
        case ..<75: return .yellow
        case ..<95: return .orange
        default:    return .red
        }
    }
}

private struct BreakdownRow: View {
    let label: String
    let value: String
    let share: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: max(2, geo.size.width * share))
                }
            }
            .frame(height: 6)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }
}

// MARK: - Formatters

private func formatNCU(_ ncu: Double) -> String {
    String(format: "%.1f", ncu)
}

private func formatRemaining(_ secs: TimeInterval) -> String {
    let s = max(0, Int(secs))
    let d = s / 86400
    let h = (s % 86400) / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m \(sec)s" }
    return "\(sec)s"
}

private func formatTimeAgo(_ date: Date, now: Date) -> String {
    let secs = Int(now.timeIntervalSince(date))
    if secs < 60   { return "\(secs)s ago" }
    if secs < 3600 { return "\(secs / 60)m ago" }
    return "\(secs / 3600)h ago"
}

private func projectName(from cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    return (cwd as NSString).lastPathComponent
}
