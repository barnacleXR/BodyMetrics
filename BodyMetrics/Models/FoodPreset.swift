import Foundation
import SwiftData

/// 常用食物库的一条。记录过的食物自动入库并累加使用次数,下次录入直接带出。
///
/// 改这里只影响以后录入时带出的默认值,已记录的 `FoodItem` 存的是当时的快照,不受影响。
@Model
final class FoodPreset {
    var name: String = ""
    var basis: FoodBasis = FoodBasis.per100g
    var servingLabel: String = ""
    var kcal: Double = 0
    var proteinG: Double = 0
    var fatG: Double = 0
    var carbG: Double = 0
    var usageCount: Int = 0
    var lastUsedAt: Date? = nil

    init(
        name: String,
        basis: FoodBasis,
        servingLabel: String = "",
        kcal: Double,
        proteinG: Double,
        fatG: Double,
        carbG: Double,
        usageCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.name = name
        self.basis = basis
        self.servingLabel = servingLabel
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbG = carbG
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
    }

    /// 副标题:"每100g · 165 kcal · P31 F3.6 C0"
    var summaryText: String {
        let basisText = basis == .per100g
            ? String(localized: "每 100 g")
            : String(localized: "每") + (servingLabel.isEmpty ? String(localized: "份") : servingLabel)
        return "\(basisText) · \(Int(kcal.rounded())) kcal · P\(StatsCalculator.format1(proteinG)) F\(StatsCalculator.format1(fatG)) C\(StatsCalculator.format1(carbG))"
    }
}
