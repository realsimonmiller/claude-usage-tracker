import Foundation

public struct UsageEntry: Sendable {
    public let timestamp: Date
    public let model: String
    public let messageId: String?
    public let requestId: String?
    public let cwd: String?
    public let inputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let outputTokens: Int

    public init(
        timestamp: Date,
        model: String,
        messageId: String? = nil,
        requestId: String? = nil,
        cwd: String? = nil,
        inputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        outputTokens: Int
    ) {
        self.timestamp = timestamp
        self.model = model
        self.messageId = messageId
        self.requestId = requestId
        self.cwd = cwd
        self.inputTokens = inputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
    }

    /// Stable key for cross-file deduplication. Claude Code writes the same
    /// turn into multiple session JSONL files when conversations are resumed
    /// or branched, so we collapse on (messageId, requestId) — matching
    /// ccusage's behavior.
    public var dedupKey: String? {
        guard let mid = messageId, let rid = requestId else { return nil }
        return "\(mid)|\(rid)"
    }

    public var totalRawTokens: Int {
        inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
    }

    public var ncu: Double {
        NCUWeights.ncu(for: self)
    }
}
