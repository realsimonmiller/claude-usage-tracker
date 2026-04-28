import Foundation

public enum JSONLParser {
    private struct AssistantLine: Decodable {
        let type: String?
        let timestamp: String?
        let requestId: String?
        let cwd: String?
        let message: MessageBlock?

        struct MessageBlock: Decodable {
            let id: String?
            let model: String?
            let usage: UsageBlock?
        }

        struct UsageBlock: Decodable {
            let input_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
            let output_tokens: Int?
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse one JSONL line into a `UsageEntry`. Returns nil for non-assistant
    /// lines, synthetic models, or lines missing required fields.
    public static func parse(line: String) -> UsageEntry? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let parsed = try? JSONDecoder().decode(AssistantLine.self, from: data) else {
            return nil
        }
        guard parsed.type == "assistant" else { return nil }
        guard let model = parsed.message?.model, !model.isEmpty, model != "<synthetic>" else {
            return nil
        }
        guard let usage = parsed.message?.usage else { return nil }
        guard let timestampStr = parsed.timestamp else { return nil }
        guard let date = parseTimestamp(timestampStr) else { return nil }

        return UsageEntry(
            timestamp: date,
            model: model,
            messageId: parsed.message?.id,
            requestId: parsed.requestId,
            cwd: parsed.cwd,
            inputTokens: usage.input_tokens ?? 0,
            cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0
        )
    }

    /// Parse all lines in a file. Reads the whole file into memory; transcripts
    /// are typically a few MB, so this is fine. For incremental tailing we'll
    /// add an offset-tracking variant in M3.
    public static func parseFile(at url: URL) -> [UsageEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var entries: [UsageEntry] = []
        contents.enumerateLines { line, _ in
            if let entry = parse(line: line) {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func parseTimestamp(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        return isoFormatterNoFraction.date(from: s)
    }
}
