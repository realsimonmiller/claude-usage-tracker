import Foundation

enum HealthBucket: Int, CaseIterable {
    case healthy
    case scuffed
    case bruised
    case bloody
    case critical
    case dead
    case evilGrin
    case noData

    var placeholderFace: String {
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

    /// SF Symbol fallback used while we don't have real Doom face sprites.
    /// These render reliably in the menu bar at 22pt regardless of emoji font issues.
    var sfSymbolName: String {
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

    var displayName: String {
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

    var demoPercent: Int {
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

    static func from(percent: Int) -> HealthBucket {
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
