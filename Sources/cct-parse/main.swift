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

printWindow(label: "rolling 5h", window: fiveHours)
printWindow(label: "rolling 7d", window: sevenDays)
