import AppKit

/// Claude mascot rendered as a draining "battery" — body fills with peach
/// when the budget is full, drains top→bottom as % used grows, and tints
/// toward red as it nears empty. Same metaphor as the macOS battery icon
/// (full → empty), just vertical and creature-shaped.
enum MascotRenderer {
    private struct CacheKey: Hashable {
        let percent: Int
        let pixelHeight: Int
    }
    private static var cache: [CacheKey: NSImage] = [:]

    /// Render the mascot at `pointHeight` points tall. Width is derived from
    /// the grid's aspect ratio so cells stay square.
    static func image(percentUsed: Int, pointHeight: CGFloat) -> NSImage {
        let percent = max(0, min(100, percentUsed))
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelHeight = Int((pointHeight * scale).rounded())
        let key = CacheKey(percent: percent, pixelHeight: pixelHeight)
        if let cached = cache[key] { return cached }
        let image = render(percentUsed: percent, pointHeight: pointHeight)
        cache[key] = image
        return image
    }

    /// 13-wide × 10-tall mascot. Wider-than-tall silhouette; the middle rows
    /// extend a column further on each side than the top/bottom rows, which
    /// gives the natural "side nub" shoulders. Eyes are 1×3 vertical bars.
    /// Four legs in a 1-2-1 grouping (cols 1, 4, 8, 11).
    /// `X` = body (drains), `K` = eye (always black), `.` = transparent.
    private static let grid: [String] = [
        ". X X X X X X X X X X X .",
        "X X X X X X X X X X X X X",
        "X X K X X X X X X X K X X",
        "X X K X X X X X X X K X X",
        "X X K X X X X X X X K X X",
        "X X X X X X X X X X X X X",
        "X X X X X X X X X X X X X",
        ". X X X X X X X X X X X .",
        ". X . . X . . . X . . X .",
        ". X . . X . . . X . . X .",
    ]

    private static func render(percentUsed: Int, pointHeight: CGFloat) -> NSImage {
        let rows = grid.count
        let cols = (grid.first ?? "").replacingOccurrences(of: " ", with: "").count
        let cellSize = pointHeight / CGFloat(rows)
        let pointWidth = cellSize * CGFloat(cols)

        let percentRemaining = 100 - percentUsed
        // Number of body rows still "filled," counted from the bottom. The
        // legs (last two rows) drain last, which feels right — the creature
        // shrinks down to its feet before disappearing.
        let filledRows = max(0, min(rows, (rows * percentRemaining + 50) / 100))
        let drainedRows = rows - filledRows

        let filledColor = filledFillColor(percentUsed: percentUsed)
        let drainedColor = NSColor(white: 0.55, alpha: 0.45)
        let eyeColor = NSColor.black

        let image = NSImage(size: NSSize(width: pointWidth, height: pointHeight))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.interpolationQuality = .none

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
                let x = CGFloat(colIdx) * cellSize
                let y = pointHeight - CGFloat(rowIdx + 1) * cellSize
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: x, y: y, width: cellSize, height: cellSize))
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
