import AppKit

/// Claude mascot rendered as a draining "battery" — body fills with peach
/// when the budget is full, drains top→bottom as % used grows, and tints
/// toward red as it nears empty. Same metaphor as the macOS battery icon
/// (full → empty), just vertical and creature-shaped.
enum MascotRenderer {
    private struct CacheKey: Hashable {
        let percent: Int
        let pixelSize: Int
    }
    private static var cache: [CacheKey: NSImage] = [:]

    static func image(percentUsed: Int, pointSize: CGFloat) -> NSImage {
        let percent = max(0, min(100, percentUsed))
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSize = Int((pointSize * scale).rounded())
        let key = CacheKey(percent: percent, pixelSize: pixelSize)
        if let cached = cache[key] { return cached }
        let image = render(percentUsed: percent, pointSize: pointSize)
        cache[key] = image
        return image
    }

    /// 9×9 pixel mascot — squat body, two black eyes, four short legs.
    /// `X` = body (drains), `K` = eye (always black), `.` = transparent.
    private static let grid: [String] = [
        ". . X X X X X . .",
        ". X X X X X X X .",
        "X X X X X X X X X",
        "X K K X X X K K X",
        "X K K X X X K K X",
        "X X X X X X X X X",
        "X X X X X X X X X",
        "X X X X X X X X X",
        ". X . X . X . X .",
    ]

    private static func render(percentUsed: Int, pointSize: CGFloat) -> NSImage {
        let cells = grid.count
        let percentRemaining = 100 - percentUsed
        // Number of rows still "filled" (counted from the bottom).
        let filledRows = max(0, min(cells, (cells * percentRemaining + 50) / 100))
        let drainedRows = cells - filledRows

        let filledColor = filledFillColor(percentUsed: percentUsed)
        let drainedColor = NSColor(white: 0.55, alpha: 0.45)
        let eyeColor = NSColor.black

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.interpolationQuality = .none

        let cellPoints = pointSize / CGFloat(cells)

        for (rowIdx, row) in grid.enumerated() {
            let chars = Array(row.replacingOccurrences(of: " ", with: ""))
            for (colIdx, ch) in chars.enumerated() {
                let color: NSColor?
                switch ch {
                case "X": color = (rowIdx < drainedRows) ? drainedColor : filledColor
                case "K": color = eyeColor
                default:  color = nil
                }
                guard let c = color else { continue }
                let x = CGFloat(colIdx) * cellPoints
                let y = pointSize - CGFloat(rowIdx + 1) * cellPoints
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: x, y: y, width: cellPoints, height: cellPoints))
            }
        }
        return image
    }

    /// Filled portion tint shifts from peach (healthy) → burnt orange → red as
    /// the budget nears empty. Drained portion stays neutral grey regardless.
    private static func filledFillColor(percentUsed: Int) -> NSColor {
        switch percentUsed {
        case ..<50:  return NSColor(red: 0.89, green: 0.48, blue: 0.37, alpha: 1) // peach
        case ..<75:  return NSColor(red: 0.89, green: 0.55, blue: 0.30, alpha: 1) // warm
        case ..<95:  return NSColor(red: 0.85, green: 0.40, blue: 0.20, alpha: 1) // burnt
        default:     return NSColor(red: 0.78, green: 0.18, blue: 0.18, alpha: 1) // danger
        }
    }
}
