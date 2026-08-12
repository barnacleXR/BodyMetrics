import Foundation

/// 记录指标类型:体重 / 体脂率
enum Metric: String, Codable, CaseIterable {
    case weight
    case bodyFat

    var label: String {
        switch self {
        case .weight: return String(localized: "体重")
        case .bodyFat: return String(localized: "体脂率")
        }
    }

    var unit: String {
        switch self {
        case .weight: return String(localized: "kg")
        case .bodyFat: return String(localized: "%")
        }
    }
}
