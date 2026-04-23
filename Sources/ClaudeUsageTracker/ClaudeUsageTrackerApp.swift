import AppKit
import ClaudeUsageTrackerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var currentBucket: HealthBucket = .healthy

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        render(bucket: currentBucket)
        rebuildMenu()

        NSLog("[CCT] launched. bucket=\(currentBucket.displayName)")
    }

    private func render(bucket: HealthBucket) {
        currentBucket = bucket
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = "\(bucket.placeholderFace) \(bucket.demoPercent)%"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: "Claude Usage Tracker — M1 demo",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        let state = NSMenuItem(
            title: "State: \(currentBucket.displayName) (\(currentBucket.demoPercent)%)",
            action: nil,
            keyEquivalent: ""
        )
        state.isEnabled = false
        menu.addItem(state)

        menu.addItem(.separator())

        let debugHeader = NSMenuItem(title: "Debug — switch face", action: nil, keyEquivalent: "")
        debugHeader.isEnabled = false
        menu.addItem(debugHeader)

        for (index, bucket) in HealthBucket.allCases.enumerated() {
            let item = NSMenuItem(
                title: "  \(bucket.placeholderFace)  \(bucket.displayName) (\(bucket.demoPercent)%)",
                action: #selector(selectBucket(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            item.target = self
            item.tag = bucket.rawValue
            item.state = (bucket == currentBucket) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func selectBucket(_ sender: NSMenuItem) {
        guard let bucket = HealthBucket(rawValue: sender.tag) else { return }
        render(bucket: bucket)
        rebuildMenu()
        NSLog("[CCT] bucket switched -> \(bucket.displayName)")
    }
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
