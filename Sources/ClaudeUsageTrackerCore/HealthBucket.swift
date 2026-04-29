import Foundation

public enum HealthBucket: Int, CaseIterable, Sendable {
    case healthy
    case scuffed
    case bruised
    case bloody
    case critical
    case dead
    case evilGrin
    case noData

    public var placeholderFace: String {
        switch self {
        case .healthy:  return "😀"
        case .scuffed:  return "🙂"
        case .bruised:  return "😐"
        case .bloody:   return "😟"
        case .critical: return "😩"
        case .dead:     return "💀"
        case .evilGrin: return "😈"
        case .noData:   return "⏳"
        }
    }

    /// SF Symbol names used in the debug force-bucket menu (emoji + label).
    /// Not shown in the normal UI — the mascot battery icon handles that.
    public var sfSymbolName: String {
        switch self {
        case .healthy:  return "face.smiling"
        case .scuffed:  return "face.smiling.inverse"
        case .bruised:  return "face.dashed"
        case .bloody:   return "exclamationmark.triangle"
        case .critical: return "exclamationmark.triangle.fill"
        case .dead:     return "xmark.octagon.fill"
        case .evilGrin: return "flame.fill"
        case .noData:   return "hourglass"
        }
    }

    public var displayName: String {
        switch self {
        case .healthy:  return "Healthy"
        case .scuffed:  return "Scuffed"
        case .bruised:  return "Bruised"
        case .bloody:   return "Bloody"
        case .critical: return "Critical"
        case .dead:     return "Dead"
        case .evilGrin: return "Evil Grin"
        case .noData:   return "No Data"
        }
    }

    public var demoPercent: Int {
        switch self {
        case .healthy:  return 12
        case .scuffed:  return 35
        case .bruised:  return 62
        case .bloody:   return 85
        case .critical: return 97
        case .dead:     return 100
        case .evilGrin: return 0
        case .noData:   return 0
        }
    }

    public static func from(percent: Int) -> HealthBucket {
        switch percent {
        case ..<20:  return .healthy
        case ..<50:  return .scuffed
        case ..<75:  return .bruised
        case ..<95:  return .bloody
        case ..<100: return .critical
        default:     return .dead
        }
    }
}
