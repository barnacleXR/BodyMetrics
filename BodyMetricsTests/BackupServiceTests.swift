import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

/// 备份往返。导入会先清空,写错就等于把用户的数据全弄丢了,必须逐类核对
@MainActor
struct BackupServiceTests {

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

    private func seed(_ context: ModelContext) {
        let profile = UserProfile(goalWeight: 58, heightCm: 172, sex: .female,
                                  birthYear: 1995, activityLevel: .moderate, weeklyRateKg: -0.25)
        profile.themePreference = .dark
        profile.hiddenBuiltinExerciseIDs = ["bench-press"]
        context.insert(profile)

        context.insert(MetricEntry(metric: .weight, value: 62.4, date: day(-1)))
        context.insert(MetricEntry(metric: .bodyFat, value: 18.6, date: day(-1)))
        context.insert(NutritionTarget(effectiveFrom: day(-3), kcal: 1800,
                                       proteinG: 110, fatG: 50, carbG: 190))

        DayLogService.addFood(
            FoodDraft(name: "鸡胸肉", basis: .per100g, amount: 200,
                      kcal: 165, proteinG: 31, fatG: 3.6, carbG: 0),
            mealType: .lunch, on: day(-1), in: context
        )
        DayLogService.addStrength(
            StrengthDraft(name: "深蹲",
                          sets: [SetDraft(reps: 10, weightKg: 60, isWarmup: true),
                                 SetDraft(reps: 5, weightKg: 100)],
                          kcalBurned: 180, kcalSource: .device),
            on: day(-1), in: context
        )
        DayLogService.addCardio(
            CardioDraft(name: "跑步机", durationMin: 30, distanceKm: 5, kcalBurned: 300),
            on: day(-1), in: context
        )
        DayLogService.setNote("状态不错", on: day(-1), in: context)
        try? context.save()
    }

    @Test func roundTripPreservesEverything() throws {
        let source = try makeContext()
        seed(source)
        let json = BackupService.exportJSON(from: source)

        let target = try makeContext()
        let result = BackupService.importJSON(json, into: target)
        guard case .restored = result else {
            Issue.record("应当按完整备份恢复,实际是 \(result)")
            return
        }

        #expect(try target.fetch(FetchDescriptor<MetricEntry>()).count == 2)
        #expect(try target.fetch(FetchDescriptor<NutritionTarget>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<DayLog>()).count == 1)

        let log = try #require(try target.fetch(FetchDescriptor<DayLog>()).first)
        #expect(log.note == "状态不错")
        #expect(log.meals.first?.items.first?.name == "鸡胸肉")
        #expect(log.meals.first?.items.first?.amount == 200)
        #expect(log.cardio.first?.distanceKm == 5)

        let workout = try #require(log.strength.first)
        #expect(workout.sets.count == 2)
        #expect(workout.volumeKg == 500)              // 热身组不计
        #expect(workout.kcalSource == .device)        // 来源要保住,它决定这个数可不可信

        let profile = try #require(try target.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(profile.sex == .female)
        #expect(profile.birthYear == 1995)
        #expect(profile.themePreference == .dark)
        #expect(profile.hiddenBuiltinExerciseIDs == ["bench-press"])
        #expect(profile.weeklyRateKg == -0.25)
    }

    @Test func importReplacesRatherThanMerges() throws {
        let source = try makeContext()
        seed(source)
        let json = BackupService.exportJSON(from: source)

        let target = try makeContext()
        // 目标库里先有一些别的数据
        DayLogService.addFood(FoodDraft(name: "别的", basis: .perServing, amount: 1, kcal: 500,
                                        proteinG: 10, fatG: 10, carbG: 50),
                              mealType: .dinner, on: today, in: target)
        target.insert(MetricEntry(metric: .weight, value: 99, date: today))
        try target.save()

        _ = BackupService.importJSON(json, into: target)

        // 合并会得到两份互相矛盾的记录,所以先清空再恢复
        #expect(try target.fetch(FetchDescriptor<DayLog>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<MetricEntry>()).count == 2)
        #expect(try target.fetch(FetchDescriptor<MetricEntry>()).allSatisfy { $0.value != 99 })
    }

    @Test func targetVersionHistorySurvivesRoundTrip() throws {
        let source = try makeContext()
        source.insert(NutritionTarget(effectiveFrom: day(-30), kcal: 2200,
                                      proteinG: 130, fatG: 70, carbG: 240))
        source.insert(NutritionTarget(effectiveFrom: day(-5), kcal: 1800,
                                      proteinG: 110, fatG: 50, carbG: 190))
        try source.save()

        let target = try makeContext()
        _ = BackupService.importJSON(BackupService.exportJSON(from: source), into: target)

        let restored = try target.fetch(FetchDescriptor<NutritionTarget>())
        #expect(restored.count == 2)
        // 版本化历史必须原样带过来,否则历史达标率会被重算
        #expect(NutritionCalculator.target(on: day(-10), in: restored)?.kcal == 2200)
        #expect(NutritionCalculator.target(on: today, in: restored)?.kcal == 1800)
    }

    @Test func prototypeAnalysisPackageRestoresNotesOnly() throws {
        let context = try makeContext()
        // HTML 原型导出的分析包(schemaVersion 3),只含汇总
        let prototypeJSON = """
        {
          "schemaVersion": 3,
          "exportedAt": "2026-08-01T00:00:00Z",
          "days": [
            { "date": "2026-07-30", "note": "外食,吃多了" },
            { "date": "2026-07-31", "note": "" }
          ]
        }
        """
        let result = BackupService.importJSON(prototypeJSON, into: context)
        guard case .prototypeSummaryOnly(let days) = result else {
            Issue.record("应当识别为原型分析包,实际是 \(result)")
            return
        }
        // 只有带备注的那天被恢复,并且照实告知只恢复了备注,不假装完整还原
        #expect(days == 1)
        #expect(try context.fetch(FetchDescriptor<DayLog>()).count == 1)
    }

    @Test func garbageInputFailsWithoutWipingData() throws {
        let context = try makeContext()
        seed(context)
        let before = try context.fetch(FetchDescriptor<DayLog>()).count

        let result = BackupService.importJSON("this is not json", into: context)
        guard case .failed = result else {
            Issue.record("非法文件应当失败,实际是 \(result)")
            return
        }
        // 解析失败绝不能已经把库清空了
        #expect(try context.fetch(FetchDescriptor<DayLog>()).count == before)
    }
}
