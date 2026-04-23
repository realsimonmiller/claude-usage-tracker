import Foundation
import ClaudeUsageTrackerCore

let fiveHours: TimeInterval = 5 * 60 * 60
let sevenDays: TimeInterval = 7 * 24 * 60 * 60

let now = Date()
let scanStart = Date()

let root = TranscriptScanner.defaultRoot
let files = TranscriptScanner.discoverTranscripts(root: root)

if files.isEmpty {
    FileHandle.standardError.write(Data("no transcripts found at \(root.path)\n".utf8))
    exit(1)
}

var rawEntries: [UsageEntry] = []
rawEntries.reserveCapacity(files.count * 100)
for file in files {
    rawEntries.append(contentsOf: JSONLParser.parseFile(at: file))
}
let allEntries = TranscriptScanner.deduplicate(rawEntries)

let scanElapsed = Date().timeIntervalSince(scanStart)

print("==> scanned \(files.count) transcript files in \(String(format: "%.2f", scanElapsed))s")
print("==> \(rawEntries.count) raw turns → \(allEntries.count) after dedup (dropped \(rawEntries.count - allEntries.count))")
print("==> root: \(root.path)")
print("")

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

func padLeft(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

func padRight(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func printWindow(label: String, window: TimeInterval) {
    let total = UsageAggregator.totals(for: allEntries, in: window, now: now)
    let byFamily = UsageAggregator.totalsByFamily(for: allEntries, in: window, now: now)

    print("┌─ \(label)")
    print("│  turns:     \(total.entryCount)")
    print("│  input:     \(formatTokens(total.inputTokens))")
    print("│  cache_w:   \(formatTokens(total.cacheCreationTokens))")
    print("│  cache_r:   \(formatTokens(total.cacheReadTokens))")
    print("│  output:    \(formatTokens(total.outputTokens))")
    print("│  raw total: \(formatTokens(total.totalRawTokens))")
    print("│  NCU:       \(String(format: "%.2f", total.ncu))")
    if !byFamily.isEmpty {
        print("│  by model family:")
        for (family, t) in byFamily {
            let pct = total.ncu > 0 ? (t.ncu / total.ncu) * 100 : 0
            let name = padRight("\(family.rawValue):", 8)
            let ncuStr = padLeft(String(format: "%.2f", t.ncu), 8)
            let pctStr = padLeft(String(format: "%.1f", pct), 5)
            print("│    \(name) NCU=\(ncuStr)  (\(pctStr)%)  turns=\(t.entryCount)")
        }
    }
    print("└─")
    print("")
}

if let block = BlockDetector.activeBlock(from: allEntries, now: now) {
    let blockTotal = block.totals
    let blockFamilies = UsageAggregator.totalsByFamily(for: block.entries, in: fiveHours, now: now)
    let remaining = block.remainingTime(now: now)
    let remH = Int(remaining) / 3600
    let remM = (Int(remaining) % 3600) / 60
    let blockStartFmt = ISO8601DateFormatter().string(from: block.startedAt)
    let blockEndFmt   = ISO8601DateFormatter().string(from: block.endsAt)
    print("┌─ active 5h block (anchored, ccusage-style)")
    print("│  started:   \(blockStartFmt)")
    print("│  ends:      \(blockEndFmt)  (in \(remH)h \(remM)m)")
    print("│  turns:     \(block.entries.count)")
    print("│  input:     \(formatTokens(blockTotal.inputTokens))")
    print("│  cache_w:   \(formatTokens(blockTotal.cacheCreationTokens))")
    print("│  cache_r:   \(formatTokens(blockTotal.cacheReadTokens))")
    print("│  output:    \(formatTokens(blockTotal.outputTokens))")
    print("│  raw total: \(formatTokens(blockTotal.totalRawTokens))")
    print("│  NCU:       \(String(format: "%.2f", blockTotal.ncu))")
    if !blockFamilies.isEmpty {
        print("│  by model family:")
        for (family, t) in blockFamilies {
            let pct = blockTotal.ncu > 0 ? (t.ncu / blockTotal.ncu) * 100 : 0
            let name = padRight("\(family.rawValue):", 8)
            let ncuStr = padLeft(String(format: "%.2f", t.ncu), 8)
            let pctStr = padLeft(String(format: "%.1f", pct), 5)
            print("│    \(name) NCU=\(ncuStr)  (\(pctStr)%)  turns=\(t.entryCount)")
        }
    }
    print("└─")
    print("")
} else {
    print("┌─ active 5h block: none (idle for >5h)")
    print("└─")
    print("")
}

printWindow(label: "rolling 5h (sliding, for comparison)", window: fiveHours)
printWindow(label: "rolling 7d", window: sevenDays)
