import Foundation

public enum ModelFamily: String, Sendable {
    case opus
    case sonnet
    case haiku
    case unknown

    public var weight: Double {
        switch self {
        case .opus:    return 5.0
        case .sonnet:  return 1.0
        case .haiku:   return 0.25
        case .unknown: return 1.0
        }
    }

    public static func from(model: String) -> ModelFamily {
        let lower = model.lowercased()
        if lower.contains("opus")   { return .opus }
        if lower.contains("sonnet") { return .sonnet }
        if lower.contains("haiku")  { return .haiku }
        return .unknown
    }
}

public enum NCUWeights {
    public static let inputWeight: Double = 1.00
    public static let cacheCreationWeight: Double = 1.25
    public static let cacheReadWeight: Double = 0.10
    public static let outputWeight: Double = 5.00

    public static func ncu(for entry: UsageEntry) -> Double {
        let modelWeight = ModelFamily.from(model: entry.model).weight
        let weightedTokens =
            inputWeight         * Double(entry.inputTokens)
          + cacheCreationWeight * Double(entry.cacheCreationTokens)
          + cacheReadWeight     * Double(entry.cacheReadTokens)
          + outputWeight        * Double(entry.outputTokens)
        return modelWeight * weightedTokens / 1_000_000.0
    }
}
