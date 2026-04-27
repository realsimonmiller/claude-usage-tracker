import AppKit
import ClaudeUsageTrackerCore

private let planDefaultsKey = "cct.planTier"
private let weeklyResetDefaultsKey = "cct.weeklyResetOverride"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: UsageMonitor!
    private var snapshot: UsageSnapshot = .empty
    private var plan: PlanTier = .pro
    private var weeklyResetOverride: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        plan = loadPlan()
        weeklyResetOverride = loadWeeklyReset()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        render(snapshot: .empty)
        rebuildMenu()

        monitor = UsageMonitor(
            plan: plan,
            weeklyResetOverride: weeklyResetOverride,
            tickInterval: 30
        ) { [weak self] snap in
            self?.snapshot = snap
            self?.render(snapshot: snap)
            self?.rebuildMenu()
        }
        monitor.start()

        NSLog("[CCT] launched. plan=\(plan.displayName) weeklyReset=\(String(describing: weeklyResetOverride))")
    }

    private func render(snapshot snap: UsageSnapshot) {
        guard let button = statusItem.button else { return }
        button.image = nil
        if snap.bucket == .noData {
            button.title = "\(HealthBucket.noData.placeholderFace) ‒"
        } else {
            button.title = "\(snap.bucket.placeholderFace) \(snap.drivingPercent)%"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Claude Usage Tracker", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if snapshot.bucket == .noData {
            let loading = NSMenuItem(title: "  Scanning transcripts…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        } else {
            menu.addItem(disabledItem("  5h:      \(formatNCU(snapshot.totals5h.ncu)) / \(formatNCU(plan.cap5h))  (\(snapshot.percent5h)%)"))
            if let block = snapshot.activeBlock {
                menu.addItem(disabledItem("           resets in \(formatRemaining(block.remainingTime()))"))
            } else {
                menu.addItem(disabledItem("           no active block (idle >5h)"))
            }
            let weeklySource = weeklyResetOverride == nil ? "auto" : "calibrated"
            menu.addItem(disabledItem("  weekly:  \(formatNCU(snapshot.totals7d.ncu)) / \(formatNCU(plan.cap7d))  (\(snapshot.percent7d)%)  [\(weeklySource)]"))
            if let week = snapshot.activeWeek {
                menu.addItem(disabledItem("           resets \(formatResetClock(week.endsAt))"))
            } else {
                menu.addItem(disabledItem("           no active week (idle >7d)"))
            }
            menu.addItem(disabledItem("  state: \(snapshot.bucket.displayName)"))
            menu.addItem(disabledItem("  entries: \(snapshot.entryCount) (after dedup)"))
            menu.addItem(disabledItem("  updated: \(formatTimeAgo(snapshot.asOf))"))
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        menu.addItem(disabledItem("Plan"))
        for tier in PlanTier.allCases {
            let item = NSMenuItem(
                title: "  \(tier.displayName)  (5h: \(Int(tier.cap5h))  ·  7d: \(Int(tier.cap7d)))",
                action: #selector(selectPlan(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = (tier == plan) ? .on : .off
            item.representedObject = tier.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let calibrate = NSMenuItem(
            title: weeklyResetOverride == nil
                ? "Calibrate weekly reset…"
                : "Recalibrate weekly reset…",
            action: #selector(calibrateWeeklyReset),
            keyEquivalent: ""
        )
        calibrate.target = self
        menu.addItem(calibrate)
        if weeklyResetOverride != nil {
            let clear = NSMenuItem(
                title: "  Clear weekly override (use auto-detect)",
                action: #selector(clearWeeklyReset),
                keyEquivalent: ""
            )
            clear.target = self
            menu.addItem(clear)
        }

        menu.addItem(.separator())

        menu.addItem(disabledItem("Debug — force bucket"))
        for (i, bucket) in HealthBucket.allCases.enumerated() {
            let item = NSMenuItem(
                title: "  \(bucket.placeholderFace)  \(bucket.displayName)",
                action: #selector(forceBucket(_:)),
                keyEquivalent: i < 9 ? "\(i + 1)" : ""
            )
            item.target = self
            item.tag = bucket.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshNow() {
        monitor.refreshNow()
    }

    @objc private func selectPlan(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tier = PlanTier(rawValue: raw) else { return }
        plan = tier
        savePlan(tier)
        monitor.setPlan(tier)
        rebuildMenu()
        NSLog("[CCT] plan -> \(tier.displayName)")
    }

    @objc private func forceBucket(_ sender: NSMenuItem) {
        guard let bucket = HealthBucket(rawValue: sender.tag) else { return }
        let fakeSnap = UsageSnapshot(
            plan: plan,
            totals5h: .zero,
            totals7d: .zero,
            percent5h: bucket.demoPercent,
            percent7d: bucket.demoPercent,
            drivingPercent: bucket.demoPercent,
            bucket: bucket,
            asOf: Date(),
            entryCount: snapshot.entryCount,
            activeBlock: nil,
            activeWeek: nil
        )
        snapshot = fakeSnap
        render(snapshot: fakeSnap)
        rebuildMenu()
    }

    private func loadPlan() -> PlanTier {
        let raw = UserDefaults.standard.string(forKey: planDefaultsKey) ?? PlanTier.pro.rawValue
        return PlanTier(rawValue: raw) ?? .pro
    }

    private func savePlan(_ tier: PlanTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: planDefaultsKey)
    }

    private func loadWeeklyReset() -> Date? {
        guard let stored = UserDefaults.standard.object(forKey: weeklyResetDefaultsKey) as? Date else {
            return nil
        }
        // Auto-roll forward if the stored reset has already passed: anchor +7d
        // until it lands in the future. Saves the user from re-entering each
        // week as long as Anthropic doesn't shift the reset day on them.
        var d = stored
        let now = Date()
        let week: TimeInterval = 7 * 24 * 60 * 60
        while d <= now { d.addTimeInterval(week) }
        if d != stored {
            UserDefaults.standard.set(d, forKey: weeklyResetDefaultsKey)
        }
        return d
    }

    private func saveWeeklyReset(_ date: Date?) {
        if let date = date {
            UserDefaults.standard.set(date, forKey: weeklyResetDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: weeklyResetDefaultsKey)
        }
    }

    @objc private func calibrateWeeklyReset() {
        let alert = NSAlert()
        alert.messageText = "Calibrate weekly reset"
        alert.informativeText = "Pick the next reset time as shown on claude.ai/settings/usage (e.g. \"Resets Sun 1:00 AM\" → set Sun at 01:00). The override re-rolls weekly."

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = weeklyResetOverride ?? Date().addingTimeInterval(24 * 3600)
        picker.minDate = Date()

        alert.accessoryView = picker
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let picked = picker.dateValue
        weeklyResetOverride = picked
        saveWeeklyReset(picked)
        monitor.setWeeklyResetOverride(picked)
        rebuildMenu()
        NSLog("[CCT] weekly reset override -> \(picked)")
    }

    @objc private func clearWeeklyReset() {
        weeklyResetOverride = nil
        saveWeeklyReset(nil)
        monitor.setWeeklyResetOverride(nil)
        rebuildMenu()
        NSLog("[CCT] weekly reset override cleared")
    }
}

private func formatNCU(_ ncu: Double) -> String {
    String(format: "%.1f", ncu)
}

private func formatTimeAgo(_ date: Date) -> String {
    let secs = Int(Date().timeIntervalSince(date))
    if secs < 60   { return "\(secs)s ago" }
    if secs < 3600 { return "\(secs / 60)m ago" }
    return "\(secs / 3600)h ago"
}

private func formatRemaining(_ secs: TimeInterval) -> String {
    let s = Int(secs)
    let d = s / 86400
    let h = (s % 86400) / 3600
    let m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private func formatResetClock(_ date: Date) -> String {
    let secs = date.timeIntervalSince(Date())
    if secs < 24 * 3600 { return "in \(formatRemaining(secs))" }
    let f = DateFormatter()
    f.dateFormat = "EEE h:mm a"
    return "\(f.string(from: date))  (in \(formatRemaining(secs)))"
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
