import AppKit
import SwiftUI
import ClaudeUsageTrackerCore

private let planDefaultsKey = "cct.planTier"
private let weeklyResetDefaultsKey = "cct.weeklyResetOverride"

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: UsageMonitor!
    private var snapshot: UsageSnapshot = .empty
    private var plan: PlanTier = .pro
    private var weeklyResetOverride: Date?

    private var popover: NSPopover!
    private var hostingController: NSHostingController<PopoverView>!
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        plan = loadPlan()
        weeklyResetOverride = loadWeeklyReset()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        render(snapshot: .empty)
        wireStatusButton()

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        hostingController = NSHostingController(rootView: makePopoverView())
        popover.contentViewController = hostingController

        monitor = UsageMonitor(
            plan: plan,
            weeklyResetOverride: weeklyResetOverride,
            tickInterval: 30
        ) { [weak self] snap in
            self?.snapshot = snap
            self?.render(snapshot: snap)
            self?.refreshPopoverContentIfNeeded()
        }
        monitor.start()

        NSLog("[CCT] launched. plan=\(plan.displayName) weeklyReset=\(String(describing: weeklyResetOverride))")
    }

    // MARK: - Status item

    private func wireStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick =
            event?.type == .rightMouseUp ||
            (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isRightClick {
            showRightClickMenu()
        } else {
            togglePopover()
        }
    }

    private func render(snapshot snap: UsageSnapshot) {
        guard let button = statusItem.button else { return }
        let mascot = MascotRenderer.image(percentUsed: snap.drivingPercent, pointSize: 18)
        mascot.isTemplate = false
        button.image = mascot
        button.imagePosition = .imageLeft
        button.imageHugsTitle = true
        if snap.bucket == .noData {
            button.title = " ‒"
        } else {
            button.title = " \(snap.drivingPercent)%"
        }
    }

    // MARK: - Popover

    private func makePopoverView() -> PopoverView {
        PopoverView(
            snapshot: snapshot,
            weeklyOverrideActive: weeklyResetOverride != nil,
            onRefresh: { [weak self] in self?.monitor.refreshNow() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        hostingController.rootView = makePopoverView()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installOutsideClickMonitor()
    }

    private func refreshPopoverContentIfNeeded() {
        guard popover.isShown else { return }
        hostingController.rootView = makePopoverView()
    }

    private func installOutsideClickMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Right-click menu

    private func showRightClickMenu() {
        let menu = NSMenu()

        menu.addItem(disabledItem("Plan"))
        for tier in PlanTier.allCases {
            let item = NSMenuItem(
                title: "  \(tier.displayName)  (5h: \(formatNCU(tier.cap5h))  ·  weekly: \(Int(tier.cap7d)))",
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
            title: weeklyResetOverride == nil ? "Calibrate weekly reset…" : "Recalibrate weekly reset…",
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

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

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
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // detach so subsequent left-clicks go back to popover
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
    }

    // MARK: - Persistence

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
        NSLog("[CCT] weekly reset override -> \(picked)")
    }

    @objc private func clearWeeklyReset() {
        weeklyResetOverride = nil
        saveWeeklyReset(nil)
        monitor.setWeeklyResetOverride(nil)
        NSLog("[CCT] weekly reset override cleared")
    }
}

private func formatNCU(_ ncu: Double) -> String {
    if ncu == ncu.rounded() { return String(format: "%.0f", ncu) }
    return String(format: "%.1f", ncu)
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
