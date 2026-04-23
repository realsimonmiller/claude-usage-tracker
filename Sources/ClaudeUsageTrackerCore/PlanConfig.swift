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

    /// NCU caps calibrated against claude.ai/settings/usage on 2026-04-23.
    /// See `docs/DESIGN.md` §7.4 for the calibration math. Max 5× is the
    /// anchor (we have direct data); Pro and Max 20× are scaled 1×/4× from it
    /// per Anthropic's standard plan ratios.
    public var cap5h: Double {
        switch self {
        case .pro:    return 5
        case .max5x:  return 25
        case .max20x: return 100
        }
    }

    public var cap7d: Double {
        switch self {
        case .pro:    return 70
        case .max5x:  return 350
        case .max20x: return 1400
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
