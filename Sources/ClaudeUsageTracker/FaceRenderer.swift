import AppKit
import ClaudeUsageTrackerCore

/// Programmatic Doom HUD-style face sprites, rendered at any size.
///
/// Each face is defined as a 9×9 grid of single-character pixels (see
/// `FaceGrids` below). Characters map to a fixed palette via `paletteColor`.
/// The rendered image is template-friendly (no bg) and cached per (bucket,
/// pixelSize) so menu-bar redraws don't re-allocate.
enum FaceRenderer {
    private static var cache: [CacheKey: NSImage] = [:]
    private struct CacheKey: Hashable {
        let bucket: HealthBucket
        let pixelSize: Int
    }

    /// Render at `pointSize` points (e.g. 22 for menu bar, 32 for popover).
    /// Honors the current screen scale so we draw at native pixel density.
    static func image(for bucket: HealthBucket, pointSize: CGFloat) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSize = Int((pointSize * scale).rounded())
        let key = CacheKey(bucket: bucket, pixelSize: pixelSize)
        if let cached = cache[key] { return cached }

        let grid = FaceGrids.grid(for: bucket)
        let image = render(grid: grid, pixelSize: pixelSize, pointSize: pointSize)
        cache[key] = image
        return image
    }

    private static func render(grid: [String], pixelSize: Int, pointSize: CGFloat) -> NSImage {
        let cells = grid.count                               // 9
        let cellPixels = max(1, pixelSize / cells)           // each "pixel" in the sprite
        let actualPixels = cellPixels * cells                // pad/trim to whole cells

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.interpolationQuality = .none

        // Map sprite-pixel coords to point coords. Top-left of grid → top-left
        // of image. Origin is bottom-left in CG; flip Y.
        let cellPoints = pointSize / CGFloat(cells)

        for (rowIdx, row) in grid.enumerated() {
            let chars = Array(row.replacingOccurrences(of: " ", with: ""))
            for (colIdx, ch) in chars.enumerated() {
                guard let color = paletteColor(for: ch) else { continue }
                let x = CGFloat(colIdx) * cellPoints
                let y = pointSize - CGFloat(rowIdx + 1) * cellPoints
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: x, y: y, width: cellPoints, height: cellPoints))
            }
        }

        _ = actualPixels  // silence
        return image
    }

    private static func paletteColor(for ch: Character) -> NSColor? {
        switch ch {
        case ".":  return nil                                    // transparent
        case "X":  return NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)  // outline
        case "S":  return NSColor(red: 0.96, green: 0.84, blue: 0.69, alpha: 1)  // skin
        case "s":  return NSColor(red: 0.84, green: 0.66, blue: 0.50, alpha: 1)  // skin shadow
        case "K":  return NSColor.black                                          // dark
        case "W":  return NSColor.white                                          // eye white
        case "P":  return NSColor.black                                          // pupil
        case "R":  return NSColor(red: 0.78, green: 0.13, blue: 0.13, alpha: 1)  // blood
        case "r":  return NSColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 1)  // dark blood
        case "B":  return NSColor(red: 0.38, green: 0.20, blue: 0.50, alpha: 1)  // bruise
        case "O":  return NSColor(red: 0.25, green: 0.05, blue: 0.05, alpha: 1)  // mouth interior
        case "G":  return NSColor(white: 0.62, alpha: 1)                         // grey
        case "Y":  return NSColor(red: 0.95, green: 0.78, blue: 0.20, alpha: 1)  // teeth/yellow
        default:   return nil
        }
    }
}

/// 9×9 ASCII grids, one per bucket. Spaces are stripped before rendering, so
/// you can pad with spaces for readability.
private enum FaceGrids {
    static func grid(for bucket: HealthBucket) -> [String] {
        switch bucket {
        case .healthy:  return healthy
        case .scuffed:  return scuffed
        case .bruised:  return bruised
        case .bloody:   return bloody
        case .critical: return critical
        case .dead:     return dead
        case .evilGrin: return evilGrin
        case .noData:   return noData
        }
    }

    static let healthy: [String] = [
        ". X X X X X X X .",
        "X S S S S S S S X",
        "X K W S S S W K X",
        "X K P S S S P K X",
        "X S S S S S S S X",
        "X S S S S S S S X",
        "X S K S S S K S X",
        "X S S K K K S S X",
        ". X S S S S S X .",
    ]

    static let scuffed: [String] = [
        ". X X X X X X X .",
        "X S S S S S S S X",
        "X K W S S S W K X",
        "X K P S S S P K X",
        "X S S s S S S S X",
        "X S S S S S r S X",
        "X S S S S S S S X",
        "X S S K K K S S X",
        ". X S S S S S X .",
    ]

    static let bruised: [String] = [
        ". X X X X X X X .",
        "X S B B s S S S X",
        "X K W S S S W K X",
        "X K P S S S P K X",
        "X S S S S S S S X",
        "X S r S S r S S X",
        "X S S S S S S S X",
        "X S S K K K S S X",
        ". X S S S S S X .",
    ]

    static let bloody: [String] = [
        ". X X X X X X X .",
        "X S R R R R S S X",
        "X K W S R S W K X",
        "X K P S R S P K X",
        "X S S R R S S S X",
        "X R S R S R S S X",
        "X S R S K O K S X",
        "X S S K O O K S X",
        ". X R S S S R X .",
    ]

    static let critical: [String] = [
        ". X X X X X X X .",
        "X R R R R R R R X",
        "X R W R R R W R X",
        "X R P R R R P R X",
        "X R R R R R R R X",
        "X R r R r R r R X",
        "X R O O O O O R X",
        "X R O Y Y Y O R X",
        ". X R R R R R X .",
    ]

    static let dead: [String] = [
        ". X X X X X X X .",
        "X G G G G G G G X",
        "X K X G G G X K X",
        "X G X K G K X G X",
        "X G G X G X G G X",
        "X G G K G K G G X",
        "X G K K K K K G X",
        "X G G K O K G G X",
        ". X G G G G G X .",
    ]

    static let evilGrin: [String] = [
        ". X X X X X X X .",
        "X S S S S S S S X",
        "X K K S S S K K X",
        "X K W S S S W K X",
        "X S S S S S S S X",
        "X S S S S S S S X",
        "X K S S S S S K X",
        "X S K Y Y Y K S X",
        ". X S K K K S X .",
    ]

    static let noData: [String] = [
        ". X X X X X X X .",
        "X G G G G G G G X",
        "X K W G G G W K X",
        "X K P G G G P K X",
        "X G G G G G G G X",
        "X G G G G G G G X",
        "X G K G G G K G X",
        "X G G K K K G G X",
        ". X G G G G G X .",
    ]
}
