import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

/// 同一条时间轴的拼装。日历、趋势、导出都从这里取数,
/// 三处各写一套按日聚合迟早会彼此对不上
@MainActor
struct FusedSeriesBuilderTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    @Test func buildsOneEntryPerDayIncludingEmptyOnes() throws {
        let context = try makeContext()
        DayLogService.addFood(FoodDraft(name: "米饭", basis: .per100g, amount: 100, kcal: 130,
                                        proteinG: 3, fatG: 0, carbG: 28),
                              mealType: .lunch, on: day(-2), in: context)

        let days = FusedSeriesBuilder.build(
            from: day(-4), to: today,
            entries: [], dayLogs: try context.fetch(FetchDescriptor<DayLog>()), targets: []
        )
        #expect(days.count == 5)
        #expect(days.filter(\.hasIntakeRecord).count == 1)
        // 没记录的日子也要占位,否则图表 x 轴会塌陷
        #expect(days.first?.intakeKcal == 0)
        #expect(days.first?.hasIntakeRecord == false)
    }

    @Test func mergesWeightAndNutritionOnTheSameDay() throws {
        let context = try makeContext()
        DayLogService.addFood(FoodDraft(name: "米饭", basis: .per100g, amount: 200, kcal: 130,
                                        proteinG: 3, fatG: 0, carbG: 28),
                              mealType: .lunch, on: today, in: context)
        let entries = [MetricEntry(metric: .weight, value: 62.4, date: today)]

        let days = FusedSeriesBuilder.build(
            from: today, to: today,
            entries: entries, dayLogs: try context.fetch(FetchDescriptor<DayLog>()), targets: []
        )
        let day = try #require(days.first)
        #expect(day.weight == 62.4)
        #expect(day.intakeKcal == 260)
        #expect(day.hasAnyRecord)
    }

    @Test func onTargetFlagFollowsTheTargetActiveThatDay() throws {
        let context = try makeContext()
        DayLogService.addFood(FoodDraft(name: "餐", basis: .perServing, amount: 1, kcal: 1900,
                                        proteinG: 100, fatG: 60, carbG: 200),
                              mealType: .lunch, on: today, in: context)
        let targets = [NutritionTarget(effectiveFrom: today, kcal: 2000,
                                       proteinG: 120, fatG: 60, carbG: 220)]

        let days = FusedSeriesBuilder.build(
            from: today, to: today,
            entries: [], dayLogs: try context.fetch(FetchDescriptor<DayLog>()), targets: targets
        )
        // 1900 在 2000 的 ±10% 内
        #expect(days.first?.isOnTarget == true)
    }

    // MARK: - streak

    @Test func streakCountsAnyKindOfRecord() throws {
        let context = try makeContext()
        // 昨天只记了饮食,前天只称了体重,今天只练了 —— 都该算打卡
        DayLogService.addFood(FoodDraft(name: "餐", basis: .perServing, amount: 1, kcal: 500,
                                        proteinG: 30, fatG: 10, carbG: 50),
                              mealType: .lunch, on: day(-1), in: context)
        DayLogService.addStrength(StrengthDraft(name: "深蹲", sets: [SetDraft(reps: 5, weightKg: 100)]),
                                  on: today, in: context)
        let entries = [MetricEntry(metric: .weight, value: 62, date: day(-2))]

        let streak = FusedSeriesBuilder.streak(
            entries: entries, dayLogs: try context.fetch(FetchDescriptor<DayLog>())
        )
        #expect(streak == 3)
    }

    @Test func streakStartsFromYesterdayWhenTodayIsStillEmpty() throws {
        let context = try makeContext()
        DayLogService.addFood(FoodDraft(name: "餐", basis: .perServing, amount: 1, kcal: 500,
                                        proteinG: 30, fatG: 10, carbG: 50),
                              mealType: .lunch, on: day(-1), in: context)
        DayLogService.addFood(FoodDraft(name: "餐", basis: .perServing, amount: 1, kcal: 500,
                                        proteinG: 30, fatG: 10, carbG: 50),
                              mealType: .lunch, on: day(-2), in: context)

        // 今天还没开始记不该把连续天数清零
        let streak = FusedSeriesBuilder.streak(
            entries: [], dayLogs: try context.fetch(FetchDescriptor<DayLog>())
        )
        #expect(streak == 2)
    }

    @Test func streakBreaksOnAGapDay() throws {
        let context = try makeContext()
        DayLogService.addFood(FoodDraft(name: "餐", basis: .perServing, amount: 1, kcal: 500,
                                        proteinG: 30, fatG: 10, carbG: 50),
                              mealType: .lunch, on: day(-1), in: context)
        DayLogService.addFood(FoodDraft(name: "餐", basis: .perServing, amount: 1, kcal: 500,
                                        proteinG: 30, fatG: 10, carbG: 50),
                              mealType: .lunch, on: day(-3), in: context)

        let streak = FusedSeriesBuilder.streak(
            entries: [], dayLogs: try context.fetch(FetchDescriptor<DayLog>())
        )
        #expect(streak == 1)
    }

    @Test func emptyDayLogsDoNotCountAsCheckIn() throws {
        let context = try makeContext()
        // 只写了备注、没有任何记录的日子不算打卡
        DayLogService.setNote("今天很累", on: day(-1), in: context)
        let streak = FusedSeriesBuilder.streak(
            entries: [], dayLogs: try context.fetch(FetchDescriptor<DayLog>())
        )
        #expect(streak == 0)
    }
}
