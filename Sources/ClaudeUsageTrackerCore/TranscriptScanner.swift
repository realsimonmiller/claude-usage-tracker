import Foundation

public enum TranscriptScanner {
    /// `~/.claude/projects` — where Claude Code writes per-session JSONL.
    public static var defaultRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Walk `root` recursively and return every `.jsonl` file found.
    public static func discoverTranscripts(root: URL = defaultRoot) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl" {
                urls.append(url)
            }
        }
        return urls
    }

    /// Discover and parse every transcript under `root`, deduplicating turns
    /// that appear in multiple session files (e.g. via `--resume`). Entries
    /// returned in no particular order; sort by timestamp at the call site
    /// if you need it.
    public static func loadAllEntries(root: URL = defaultRoot) -> [UsageEntry] {
        let files = discoverTranscripts(root: root)
        var all: [UsageEntry] = []
        for file in files {
            all.append(contentsOf: JSONLParser.parseFile(at: file))
        }
        return deduplicate(all)
    }

    /// Drop entries that share a `(messageId, requestId)` key. Entries without
    /// a dedup key (legacy lines missing one of those fields) are kept as-is.
    public static func deduplicate(_ entries: [UsageEntry]) -> [UsageEntry] {
        var seen = Set<String>()
        var out: [UsageEntry] = []
        out.reserveCapacity(entries.count)
        for e in entries {
            if let key = e.dedupKey {
                if seen.insert(key).inserted {
                    out.append(e)
                }
            } else {
                out.append(e)
            }
        }
        return out
    }
}
