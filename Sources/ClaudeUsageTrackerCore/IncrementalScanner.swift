import Foundation

/// Tails Claude Code's JSONL transcripts incrementally. The first call to
/// `loadInitial()` walks every transcript end-to-end (slow — ~10s on a large
/// history). After that, `applyChanges(forPaths:)` only re-reads the suffix
/// of files whose size changed, keyed by byte offset.
///
/// All public methods are NOT thread-safe — call them from a single serial
/// queue. `UsageMonitor` provides that.
public final class IncrementalScanner {
    private struct FileState {
        var offset: Int64
        var size: Int64
    }

    private let root: URL
    private var fileStates: [URL: FileState] = [:]
    /// Deduped entries keyed by `(messageId, requestId)`.
    private var entriesByKey: [String: UsageEntry] = [:]
    /// Entries lacking a dedup key — kept as-is.
    private var orphanEntries: [UsageEntry] = []

    public init(root: URL = TranscriptScanner.defaultRoot) {
        self.root = root
    }

    /// Walk every transcript under `root` and ingest from offset 0. Returns
    /// the deduplicated entry set after the load completes.
    @discardableResult
    public func loadInitial() -> [UsageEntry] {
        let urls = TranscriptScanner.discoverTranscripts(root: root)
        for url in urls {
            ingest(url: url)
        }
        return currentEntries()
    }

    /// Re-discover transcripts under `root` and ingest only the suffix of
    /// each file whose size grew (or whose contents shrank — treated as a
    /// rotation and re-read from 0). Pass an explicit `forPaths` set to skip
    /// directory rediscovery when you trust FSEvents to have given you the
    /// exact list.
    @discardableResult
    public func applyChanges(forPaths candidates: Set<String>? = nil) -> [UsageEntry] {
        let allUrls = TranscriptScanner.discoverTranscripts(root: root)
        let urls: [URL]
        if let candidates = candidates {
            urls = allUrls.filter { candidates.contains($0.path) || fileStates[$0] == nil }
        } else {
            urls = allUrls
        }
        for url in urls {
            if needsRead(url) {
                ingest(url: url)
            }
        }
        return currentEntries()
    }

    public func currentEntries() -> [UsageEntry] {
        var out: [UsageEntry] = []
        out.reserveCapacity(entriesByKey.count + orphanEntries.count)
        out.append(contentsOf: entriesByKey.values)
        out.append(contentsOf: orphanEntries)
        return out
    }

    private func needsRead(_ url: URL) -> Bool {
        guard let size = fileSize(at: url) else { return false }
        guard let state = fileStates[url] else { return true }
        return size != state.size
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    private func ingest(url: URL) {
        guard let size = fileSize(at: url) else { return }

        var startOffset: Int64 = 0
        if let state = fileStates[url], size >= state.size {
            startOffset = state.offset
        }
        if size <= startOffset {
            // Nothing new (or file shrunk to or below offset — record current
            // size so we re-read on next growth).
            fileStates[url] = FileState(offset: startOffset, size: size)
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(startOffset))
        } catch {
            return
        }
        let data = handle.readDataToEndOfFile()
        if data.isEmpty {
            fileStates[url] = FileState(offset: startOffset, size: size)
            return
        }

        // Find the byte position of the last newline so we don't try to parse
        // a partial line that's still mid-write.
        let newline = UInt8(ascii: "\n")
        var lastNewlineByteIndex: Int? = nil
        var i = data.count - 1
        while i >= 0 {
            if data[i] == newline {
                lastNewlineByteIndex = i
                break
            }
            i -= 1
        }

        guard let nlIdx = lastNewlineByteIndex else {
            // No complete line — wait for more data; keep offset unchanged.
            fileStates[url] = FileState(offset: startOffset, size: size)
            return
        }

        let completeData = data.prefix(nlIdx + 1)
        if let text = String(data: completeData, encoding: .utf8) {
            text.enumerateLines { line, _ in
                guard let entry = JSONLParser.parse(line: line) else { return }
                if let key = entry.dedupKey {
                    self.entriesByKey[key] = entry
                } else {
                    self.orphanEntries.append(entry)
                }
            }
        }

        fileStates[url] = FileState(
            offset: startOffset + Int64(nlIdx + 1),
            size: size
        )
    }
}
