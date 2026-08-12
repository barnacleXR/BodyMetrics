import Foundation

/// 一天的饮食与训练汇总
struct DayTotals: Equatable {
    var macros: MacroTotals = .zero
    /// 训练消耗(力量 + 有氧)
    var burnedKcal: Double = 0
    /// 力量训练容量,热身组不计
    var volumeKg: Double = 0

    static let zero = DayTotals()
}

/// 相对目标的剩余额度
struct RemainingBudget: Equatable {
    /// 当日可用热量(目标 + 可选的训练回补)
    var budgetKcal: Double = 0
    var kcal: Double = 0
    var proteinG: Double = 0
    var fatG: Double = 0
    var carbG: Double = 0
}

/// 营养与训练的纯计算层(无 SwiftData / SwiftUI 依赖,全部可单测)
enum NutritionCalculator {

    // MARK: - 基础代谢与 TDEE

    /// Mifflin-St Jeor 基础代谢率。任一入参缺失时返回 0(而不是编一个数)
    static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        guard weightKg > 0, heightCm > 0, age > 0 else { return 0 }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return (sex == .female ? base - 161 : base + 5).rounded()
    }

    /// 每日总消耗 = BMR × 活动系数。
    /// 体重是入参而非 profile 字段——它来自最新一条体重记录,体重变则 TDEE 自动跟着变
    static func tdee(sex: Sex, weightKg: Double, heightCm: Double, age: Int, activityLevel: ActivityLevel) -> Double {
        (bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age) * activityLevel.factor).rounded()
    }

    // MARK: - 宏量目标

    /// 由热量额度推一组宏量:蛋白 1.6 g/kg,脂肪占 25% 热量,碳水补足
    static func macros(forKcal kcal: Double, weightKg: Double) -> MacroTotals {
        guard kcal > 0 else { return .zero }
        let protein = (weightKg * 1.6).rounded()
        let fat = (kcal * 0.25 / 9).rounded()
        let carb = max(0, (kcal - protein * 4 - fat * 9) / 4).rounded()
        return MacroTotals(kcal: kcal.rounded(), proteinG: protein, fatG: fat, carbG: carb)
    }

    // MARK: - 份量换算

    /// 按基准换算单条食物的实际营养贡献
    static func scaled(
        basis: FoodBasis,
        amount: Double,
        kcal: Double,
        proteinG: Double,
        fatG: Double,
        carbG: Double
    ) -> MacroTotals {
        let factor = basis == .per100g ? amount / 100 : amount
        return MacroTotals(
            kcal: kcal * factor,
            proteinG: proteinG * factor,
            fatG: fatG * factor,
            carbG: carbG * factor
        )
    }

    // MARK: - 力量

    /// Epley 一次最大重量估算
    static func e1rm(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return (weightKg * (1 + Double(reps) / 30)).rounded()
    }

    // MARK: - 当日汇总

    static func totals(for day: DayLog) -> DayTotals {
        var result = DayTotals()
        for meal in day.meals {
            for item in meal.items {
                result.macros = result.macros + item.scaled
            }
        }
        for session in day.cardio {
            result.burnedKcal += session.kcalBurned
        }
        for workout in day.strength {
            result.burnedKcal += workout.kcalBurned
            result.volumeKg += workout.volumeKg
        }
        return result
    }

    // MARK: - 剩余额度

    /// 剩余额度。`addBurnedToBudget` 为 false 时训练消耗不回补:
    /// 活动系数已经包含日常活动,回补会双重计算。
    /// `draft` 是试算购物车的汇总,只影响显示不落盘。
    static func remaining(
        totals: DayTotals,
        target: MacroTotals?,
        addBurnedToBudget: Bool,
        draft: MacroTotals = .zero
    ) -> RemainingBudget {
        let target = target ?? .zero
        let budget = target.kcal + (addBurnedToBudget ? totals.burnedKcal : 0)
        return RemainingBudget(
            budgetKcal: budget.rounded(),
            kcal: (budget - totals.macros.kcal - draft.kcal).rounded(),
            proteinG: round1(target.proteinG - totals.macros.proteinG - draft.proteinG),
            fatG: round1(target.fatG - totals.macros.fatG - draft.fatG),
            carbG: round1(target.carbG - totals.macros.carbG - draft.carbG)
        )
    }

    // MARK: - 目标版本

    /// 某日适用的目标 = 所有 effectiveFrom <= 该日 中最晚的一条。
    /// 改目标不重写历史:昨天的达标与否不会因为今天调目标而变化
    static func target(on day: Date, in targets: [NutritionTarget], calendar: Calendar = .current) -> NutritionTarget? {
        let dayStart = calendar.startOfDay(for: day)
        return targets
            .filter { calendar.startOfDay(for: $0.effectiveFrom) <= dayStart }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// 热量是否达标(相对目标 ±10% 以内)
    static func isKcalOnTarget(_ kcal: Double, target: Double) -> Bool {
        guard target > 0 else { return false }
        return abs(kcal - target) <= target * 0.1
    }

    // MARK: - 格式化

    static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
