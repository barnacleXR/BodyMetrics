import Testing
import Foundation
@testable import BodyMetrics

struct NutritionCalculatorTests {

    // MARK: - 基础代谢

    @Test func bmrFollowsMifflinStJeor() {
        // 男:10×70 + 6.25×175 − 5×30 + 5 = 1648.75 → 1649
        #expect(NutritionCalculator.bmr(sex: .male, weightKg: 70, heightCm: 175, age: 30) == 1649)
        // 女:同样身高体重年龄,− 161 而非 + 5,相差 166
        #expect(NutritionCalculator.bmr(sex: .female, weightKg: 70, heightCm: 175, age: 30) == 1483)
    }

    @Test func bmrReturnsZeroWhenProfileIncomplete() {
        #expect(NutritionCalculator.bmr(sex: .male, weightKg: 0, heightCm: 175, age: 30) == 0)
        #expect(NutritionCalculator.bmr(sex: .male, weightKg: 70, heightCm: 0, age: 30) == 0)
        // 出生年未设置时 age 为 0,不能凭空编一个基础代谢出来
        #expect(NutritionCalculator.bmr(sex: .male, weightKg: 70, heightCm: 175, age: 0) == 0)
    }

    @Test func tdeeAppliesActivityFactor() {
        let bmr = NutritionCalculator.bmr(sex: .male, weightKg: 70, heightCm: 175, age: 30)
        let tdee = NutritionCalculator.tdee(
            sex: .male, weightKg: 70, heightCm: 175, age: 30, activityLevel: .moderate
        )
        #expect(tdee == (bmr * 1.55).rounded())
    }

    // MARK: - 宏量推荐

    @Test func macrosUseProteinPerKgFatShareAndCarbRemainder() {
        let macros = NutritionCalculator.macros(forKcal: 2000, weightKg: 70)
        #expect(macros.proteinG == 112)            // 70 × 1.6
        #expect(macros.fatG == 56)                 // 2000 × 25% ÷ 9 = 55.6 → 56
        // 碳水补足:(2000 − 112×4 − 56×9) ÷ 4 = 262
        #expect(macros.carbG == 262)
    }

    @Test func macrosNeverGoNegative() {
        // 极低热量下碳水补足会算成负数,必须钳到 0
        let macros = NutritionCalculator.macros(forKcal: 600, weightKg: 90)
        #expect(macros.carbG >= 0)
    }

    // MARK: - 份量换算

    @Test func scalingUsesPer100gOrPerServing() {
        let per100 = NutritionCalculator.scaled(
            basis: .per100g, amount: 150, kcal: 165, proteinG: 31, fatG: 3.6, carbG: 0
        )
        #expect(abs(per100.kcal - 247.5) < 0.001)
        #expect(abs(per100.proteinG - 46.5) < 0.001)

        let perServing = NutritionCalculator.scaled(
            basis: .perServing, amount: 2, kcal: 80, proteinG: 6, fatG: 5, carbG: 1
        )
        #expect(abs(perServing.kcal - 160) < 0.001)
    }

    // MARK: - 力量

    @Test func e1rmUsesEpleyAndPassesThroughSingles() {
        #expect(NutritionCalculator.e1rm(weightKg: 100, reps: 1) == 100)
        // 100 × (1 + 5/30) = 116.67 → 117
        #expect(NutritionCalculator.e1rm(weightKg: 100, reps: 5) == 117)
        #expect(NutritionCalculator.e1rm(weightKg: 0, reps: 5) == 0)
    }

    @Test func volumeAndBestE1rmSkipWarmupSets() {
        let workout = StrengthWorkout(name: "深蹲")
        workout.sets = [
            StrengthSet(reps: 10, weightKg: 200, isWarmup: true, sortIndex: 0),
            StrengthSet(reps: 5, weightKg: 100, isWarmup: false, sortIndex: 1),
            StrengthSet(reps: 5, weightKg: 100, isWarmup: false, sortIndex: 2),
        ]
        // 热身组那 2000 kg 不能算进容量,否则容量趋势会被热身重量带偏
        #expect(workout.volumeKg == 1000)
        #expect(workout.bestE1RM == 117)
    }

    // MARK: - 当日汇总与剩余额度

    private func makeDay() -> DayLog {
        let day = DayLog(dayStart: Calendar.current.startOfDay(for: .now))
        let meal = Meal(type: .lunch)
        meal.items = [
            FoodItem(name: "鸡胸肉", basis: .per100g, amount: 200,
                     kcal: 165, proteinG: 31, fatG: 3.6, carbG: 0),
            FoodItem(name: "米饭", basis: .perServing, servingLabel: "碗", amount: 1,
                     kcal: 200, proteinG: 4, fatG: 0.5, carbG: 44),
        ]
        day.meals = [meal]

        let cardio = CardioSession(name: "跑步机", durationMin: 30, kcalBurned: 300)
        day.cardio = [cardio]
        return day
    }

    @Test func totalsSumMealsAndBurn() {
        let totals = NutritionCalculator.totals(for: makeDay())
        #expect(abs(totals.macros.kcal - 530) < 0.001)      // 165×2 + 200
        #expect(abs(totals.macros.proteinG - 66) < 0.001)   // 31×2 + 4
        #expect(totals.burnedKcal == 300)
    }

    @Test func burnedCaloriesDoNotRefundBudgetByDefault() {
        let totals = NutritionCalculator.totals(for: makeDay())
        let target = MacroTotals(kcal: 2000, proteinG: 120, fatG: 60, carbG: 200)

        let without = NutritionCalculator.remaining(
            totals: totals, target: target, addBurnedToBudget: false
        )
        #expect(without.budgetKcal == 2000)
        #expect(without.kcal == 1470)

        // 开启回补时训练消耗才计入额度(活动系数已含日常活动,故默认关闭)
        let with = NutritionCalculator.remaining(
            totals: totals, target: target, addBurnedToBudget: true
        )
        #expect(with.budgetKcal == 2300)
        #expect(with.kcal == 1770)
    }

    @Test func draftReducesRemainingWithoutTouchingRecords() {
        let totals = NutritionCalculator.totals(for: makeDay())
        let target = MacroTotals(kcal: 2000, proteinG: 120, fatG: 60, carbG: 200)
        let draft = MacroTotals(kcal: 400, proteinG: 20, fatG: 10, carbG: 50)

        let result = NutritionCalculator.remaining(
            totals: totals, target: target, addBurnedToBudget: false, draft: draft
        )
        #expect(result.kcal == 1070)
        #expect(result.proteinG == 34)
    }

    // MARK: - 目标版本化

    @Test func targetForDatePicksLatestEffectiveOnOrBefore() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let old = NutritionTarget(
            effectiveFrom: calendar.date(byAdding: .day, value: -30, to: today)!,
            kcal: 1800, proteinG: 100, fatG: 50, carbG: 200
        )
        let recent = NutritionTarget(
            effectiveFrom: calendar.date(byAdding: .day, value: -5, to: today)!,
            kcal: 2000, proteinG: 120, fatG: 60, carbG: 220
        )
        let targets = [old, recent]

        // 10 天前那一天应当仍然适用旧目标——改目标不能重写历史达标率
        let past = calendar.date(byAdding: .day, value: -10, to: today)!
        #expect(NutritionCalculator.target(on: past, in: targets)?.kcal == 1800)
        #expect(NutritionCalculator.target(on: today, in: targets)?.kcal == 2000)

        // 第一条目标生效之前没有目标可用
        let ancient = calendar.date(byAdding: .day, value: -60, to: today)!
        #expect(NutritionCalculator.target(on: ancient, in: targets) == nil)
    }

    @Test func kcalOnTargetWithinTenPercent() {
        #expect(NutritionCalculator.isKcalOnTarget(2100, target: 2000))
        #expect(NutritionCalculator.isKcalOnTarget(1800, target: 2000))
        #expect(!NutritionCalculator.isKcalOnTarget(2201, target: 2000))
        #expect(!NutritionCalculator.isKcalOnTarget(1500, target: 0))
    }
}
