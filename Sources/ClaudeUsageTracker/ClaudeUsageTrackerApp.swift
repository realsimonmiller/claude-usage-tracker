import AppKit
import ClaudeUsageTrackerCore

private let planDefaultsKey = "cct.planTier"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: UsageMonitor!
    private var snapshot: UsageSnapshot = .empty
    private var plan: PlanTier = .pro

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        plan = loadPlan()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        render(snapshot: .empty)
        rebuildMenu()

        monitor = UsageMonitor(plan: plan, tickInterval: 30) { [weak self] snap in
            self?.snapshot = snap
            self?.render(snapshot: snap)
            self?.rebuildMenu()
        }
        monitor.start()

        NSLog("[CCT] launched. plan=\(plan.displayName)")
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
            menu.addItem(disabledItem("  5h:  \(formatNCU(snapshot.totals5h.ncu)) / \(formatNCU(plan.cap5h))  (\(snapshot.percent5h)%)"))
            if let block = snapshot.activeBlock {
                menu.addItem(disabledItem("       resets in \(formatRemaining(block.remainingTime()))"))
            } else {
                menu.addItem(disabledItem("       no active block (idle >5h)"))
            }
            menu.addItem(disabledItem("  7d:  \(formatNCU(snapshot.totals7d.ncu)) / \(formatNCU(plan.cap7d))  (\(snapshot.percent7d)%)"))
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
            activeBlock: nil
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
    let h = s / 3600
    let m = (s % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
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
