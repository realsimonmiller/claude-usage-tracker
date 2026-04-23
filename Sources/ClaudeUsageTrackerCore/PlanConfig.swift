import Foundation

public enum PlanTier: String, CaseIterable, Sendable {
    case pro
    case max5x
    case max20x

    public var displayName: String {
        switch self {
        case .pro:    return "Pro"
        case .max5x:  return "Max 5×"
        case .max20x: return "Max 20×"
        }
    }

    /// Heuristic NCU caps per `docs/DESIGN.md` §7.4.
    public var cap5h: Double {
        switch self {
        case .pro:    return 50
        case .max5x:  return 250
        case .max20x: return 1000
        }
    }

    public var cap7d: Double {
        switch self {
        case .pro:    return 350
        case .max5x:  return 1750
        case .max20x: return 7000
        }
    }
}

public struct PlanConfig: Sendable {
    public let tier: PlanTier
    public var cap5h: Double { tier.cap5h }
    public var cap7d: Double { tier.cap7d }

    public init(tier: PlanTier) {
        self.tier = tier
    }
}
