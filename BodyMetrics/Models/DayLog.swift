import Foundation
import SwiftData

/// 一天的饮食与训练容器。
///
/// 体重不放在这里:体重是 `MetricEntry`(追加式、带精确时间戳、同日可多条),
/// 硬塞进来会破坏"当日最新一条"的语义。两者在计算层按日期关联,
/// 融合发生在计算层与视图层,而不是靠合并存储。
@Model
final class DayLog {
    /// 当天零点(本地时区),唯一键。一律用 Calendar.startOfDay 归一,禁止 UTC 转换
    @Attribute(.unique) var dayStart: Date = Date.now
    var note: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Meal.dayLog)
    var meals: [Meal] = []

    @Relationship(deleteRule: .cascade, inverse: \StrengthWorkout.dayLog)
    var strength: [StrengthWorkout] = []

    @Relationship(deleteRule: .cascade, inverse: \CardioSession.dayLog)
    var cardio: [CardioSession] = []

    init(dayStart: Date, note: String = "") {
        self.dayStart = dayStart
        self.note = note
    }

    /// 没有任何饮食与训练记录(备注不计:只写了备注不算打卡)
    var isEmpty: Bool {
        meals.allSatisfy { $0.items.isEmpty } && strength.isEmpty && cardio.isEmpty
    }

    /// 按餐次固定顺序排列,且过滤掉空餐次
    var sortedMeals: [Meal] {
        meals.filter { !$0.items.isEmpty }.sorted { $0.type.order < $1.type.order }
    }
}
