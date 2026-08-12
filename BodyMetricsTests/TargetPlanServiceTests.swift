import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

@MainActor
struct TargetPlanServiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    @Test func savingTwiceInOneDayUpdatesInsteadOfPilingUp() throws {
        let context = try makeContext()
        TargetPlanService.saveTarget(MacroTotals(kcal: 2000, proteinG: 120, fatG: 60, carbG: 200), in: context)
        TargetPlanService.saveTarget(MacroTotals(kcal: 1800, proteinG: 110, fatG: 50, carbG: 190), in: context)

        let targets = try context.fetch(FetchDescriptor<NutritionTarget>())
        #expect(targets.count == 1)
        #expect(targets.first?.kcal == 1800)
    }

    @Test func newTargetDoesNotRewriteYesterdaysTarget() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        context.insert(NutritionTarget(effectiveFrom: yesterday, kcal: 2200,
                                       proteinG: 130, fatG: 70, carbG: 240))
        try context.save()

        TargetPlanService.saveTarget(MacroTotals(kcal: 1800, proteinG: 110, fatG: 50, carbG: 190), in: context)

        let all = try context.fetch(FetchDescriptor<NutritionTarget>())
        #expect(all.count == 2)
        // 昨天仍然按昨天的目标算达标,不被今天的调整追溯改写
        #expect(NutritionCalculator.target(on: yesterday, in: all)?.kcal == 2200)
        #expect(NutritionCalculator.target(on: today, in: all)?.kcal == 1800)
    }

    @Test func planUsesLatestWeightRatherThanAStoredNumber() throws {
        let context = try makeContext()
        let profile = UserProfile(goalWeight: 65, heightCm: 175, sex: .male,
                                  birthYear: Calendar.current.component(.year, from: .now) - 30,
                                  activityLevel: .moderate, weeklyRateKg: -0.5)
        context.insert(profile)

        let entries = [
            MetricEntry(metric: .weight, value: 80, date: Calendar.current.date(byAdding: .day, value: -30, to: today)!),
            MetricEntry(metric: .weight, value: 70, date: today),
        ]
        let plan = try #require(TargetPlanService.currentPlan(profile: profile, entries: entries))

        // 用最新的 70kg 而不是最早的 80kg:体重变了 TDEE 要跟着变
        let expected = NutritionCalculator.tdee(sex: .male, weightKg: 70, heightCm: 175,
                                                age: 30, activityLevel: .moderate)
        #expect(plan.tdeeKcal == expected)
        #expect(plan.macros.proteinG == 112)   // 70 × 1.6
    }

    @Test func planIsNilWithoutAnyWeightRecord() throws {
        let context = try makeContext()
        let profile = UserProfile(birthYear: 1995)
        context.insert(profile)
        // 没有体重就没有基础代谢,不能编一个目标出来
        #expect(TargetPlanService.currentPlan(profile: profile, entries: []) == nil)
    }

    @Test func planIsNilWithoutBirthYear() throws {
        let context = try makeContext()
        let profile = UserProfile()   // birthYear 默认 0 = 未设置
        context.insert(profile)
        let entries = [MetricEntry(metric: .weight, value: 70, date: today)]
        #expect(TargetPlanService.currentPlan(profile: profile, entries: entries) == nil)
    }

    @Test func hasAnyTargetReflectsWhetherOneWasSaved() throws {
        let context = try makeContext()
        #expect(!TargetPlanService.hasAnyTarget(in: context))
        TargetPlanService.saveTarget(MacroTotals(kcal: 2000, proteinG: 120, fatG: 60, carbG: 200), in: context)
        #expect(TargetPlanService.hasAnyTarget(in: context))
    }
}
