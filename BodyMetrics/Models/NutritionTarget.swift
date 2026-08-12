import Foundation
import SwiftData

/// 一段时间内生效的每日营养目标。
///
/// 目标是**版本化**的:某日适用的目标 = 所有 `effectiveFrom <= 该日` 中最晚的一条。
/// 改目标只影响今天起的日子,绝不重写历史达标率——否则昨天"达标"会因为今天调目标而变成"未达标"。
@Model
final class NutritionTarget {
    /// 生效起始日(当天零点)
    var effectiveFrom: Date = Date.now
    var kcal: Double = 0
    var proteinG: Double = 0
    var fatG: Double = 0
    var carbG: Double = 0

    init(effectiveFrom: Date, kcal: Double, proteinG: Double, fatG: Double, carbG: Double) {
        self.effectiveFrom = effectiveFrom
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbG = carbG
    }

    var macros: MacroTotals {
        MacroTotals(kcal: kcal, proteinG: proteinG, fatG: fatG, carbG: carbG)
    }
}
