import Foundation

/// 性别(仅用于 Mifflin-St Jeor 基础代谢公式)
enum Sex: String, Codable, CaseIterable {
    case male
    case female

    var label: String {
        switch self {
        case .male: return String(localized: "男")
        case .female: return String(localized: "女")
        }
    }
}

/// 活动强度系数(TDEE = BMR × factor)。系数已包含日常活动,这是训练消耗默认不回补额度的原因
enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary
    case light
    case moderate
    case active

    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        }
    }

    var label: String {
        switch self {
        case .sedentary: return String(localized: "久坐")
        case .light: return String(localized: "轻度活动")
        case .moderate: return String(localized: "中度活动")
        case .active: return String(localized: "高度活动")
        }
    }
}

/// 外观偏好
enum ThemePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .light: return String(localized: "浅色")
        case .dark: return String(localized: "深色")
        }
    }
}

/// 餐次
enum MealType: String, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack

    var label: String {
        switch self {
        case .breakfast: return String(localized: "早餐")
        case .lunch: return String(localized: "午餐")
        case .dinner: return String(localized: "晚餐")
        case .snack: return String(localized: "加餐")
        }
    }

    /// 列表展示顺序
    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }
}

/// 营养基准:每 100 g,或每份
enum FoodBasis: String, Codable, CaseIterable {
    case per100g
    case perServing

    var label: String {
        switch self {
        case .per100g: return String(localized: "每 100 g")
        case .perServing: return String(localized: "每份")
        }
    }
}

/// 消耗热量的来源。device 来源误差可达 ±25%,导出与能量平衡计算时必须区别对待
enum KcalSource: String, Codable, CaseIterable {
    case manual
    case device

    var label: String {
        switch self {
        case .manual: return String(localized: "手动填写")
        case .device: return String(localized: "设备读数")
        }
    }
}

/// 动作类型
enum ExerciseKind: String, Codable, CaseIterable {
    case strength
    case cardio

    var label: String {
        switch self {
        case .strength: return String(localized: "力量")
        case .cardio: return String(localized: "有氧")
        }
    }
}

/// 提醒类型(只影响通知文案)
enum ReminderKind: String, Codable, CaseIterable {
    case weighIn
    case meal
    case postWorkout

    var label: String {
        switch self {
        case .weighIn: return String(localized: "晨间称重")
        case .meal: return String(localized: "记录饮食")
        case .postWorkout: return String(localized: "训练后记录")
        }
    }

    var notificationBody: String {
        switch self {
        case .weighIn: return String(localized: "花 10 秒记录今天的体重")
        case .meal: return String(localized: "记一下这一餐,别等到晚上回忆")
        case .postWorkout: return String(localized: "把刚才的训练记下来")
        }
    }
}
