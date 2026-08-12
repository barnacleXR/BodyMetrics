import Foundation
import SwiftData

/// 一条食物记录。
///
/// 营养值是**记录当时的快照**,不引用 `FoodPreset`——改食物库只影响以后录入时
/// 带出的默认值,已经记过的内容不被追溯修改。
@Model
final class FoodItem {
    var name: String = ""
    /// 营养值的基准:每 100 g,或每份
    var basis: FoodBasis = FoodBasis.per100g
    /// 一份的说法(个 / 碗 / 盒),仅 perServing 时有意义
    var servingLabel: String = ""
    /// 份量:per100g 时是克数,perServing 时是份数
    var amount: Double = 0
    /// 以下四项均为"每基准"的值,不是本条的总量
    var kcal: Double = 0
    var proteinG: Double = 0
    var fatG: Double = 0
    var carbG: Double = 0

    var meal: Meal?

    init(
        name: String,
        basis: FoodBasis,
        servingLabel: String = "",
        amount: Double,
        kcal: Double,
        proteinG: Double,
        fatG: Double,
        carbG: Double
    ) {
        self.name = name
        self.basis = basis
        self.servingLabel = servingLabel
        self.amount = amount
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbG = carbG
    }

    /// 本条实际贡献的营养
    var scaled: MacroTotals {
        NutritionCalculator.scaled(
            basis: basis, amount: amount,
            kcal: kcal, proteinG: proteinG, fatG: fatG, carbG: carbG
        )
    }

    /// 份量的展示文本,如 "150 g" / "1.5 碗"
    var amountText: String {
        let number = amount == amount.rounded() ? String(Int(amount)) : StatsCalculator.format1(amount)
        return basis == .per100g ? "\(number) g" : "\(number) \(servingLabel.isEmpty ? String(localized: "份") : servingLabel)"
    }
}

/// 四项宏量的汇总值(纯数据,不进 SwiftData)
struct MacroTotals: Equatable {
    var kcal: Double = 0
    var proteinG: Double = 0
    var fatG: Double = 0
    var carbG: Double = 0

    static let zero = MacroTotals()

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            kcal: lhs.kcal + rhs.kcal,
            proteinG: lhs.proteinG + rhs.proteinG,
            fatG: lhs.fatG + rhs.fatG,
            carbG: lhs.carbG + rhs.carbG
        )
    }
}
