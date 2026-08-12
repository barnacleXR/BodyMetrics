import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

/// 导出包必须同时带上体重与能量收支结论——AI 能对照"吃了多少"和"体重怎么响应",
/// 才谈得上给有依据的建议。只导饮食就退回成了原型能做的事
@MainActor
struct AIExportBuilderTests {

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

    private func buildPayload(
        adaptive: EnergyBalanceService.AdaptiveTDEE = .insufficientData(reason: "测试")
    ) throws -> AIExportBuilder.Payload {
        let context = try makeContext()
        let profile = UserProfile(goalWeight: 58, heightCm: 172, sex: .male,
                                  birthYear: 1995, activityLevel: .moderate)
        context.insert(profile)

        DayLogService.addFood(
            FoodDraft(name: "鸡胸肉", basis: .per100g, amount: 200,
                      kcal: 165, proteinG: 31, fatG: 3.6, carbG: 0),
            mealType: .lunch, on: day(-1), in: context
        )
        DayLogService.addStrength(
            StrengthDraft(name: "深蹲", sets: [SetDraft(reps: 5, weightKg: 100)],
                          kcalBurned: 200, kcalSource: .device),
            on: day(-1), in: context
        )
        let entries = [
            MetricEntry(metric: .weight, value: 63.0, date: day(-2)),
            MetricEntry(metric: .weight, value: 62.4, date: day(-1)),
        ]
        for entry in entries { context.insert(entry) }
        try context.save()

        let dayLogs = try context.fetch(FetchDescriptor<DayLog>())
        let days = FusedSeriesBuilder.build(
            from: day(-3), to: today,
            entries: entries, dayLogs: dayLogs, targets: [], calendar: calendar
        )
        return AIExportBuilder.build(
            days: days, dayLogs: dayLogs, entries: entries, targets: [],
            profile: profile, adaptive: adaptive, formulaTDEE: 2000,
            prompt: AIExportBuilder.prompt(singleDay: false, mentionsJSONFields: true), calendar: calendar
        )
    }

    @Test func payloadCarriesWeightAlongsideNutrition() throws {
        let payload = try buildPayload()
        // 同一天里体重与饮食并存,这正是融合导出的意义
        let dayWithBoth = try #require(payload.days.first { $0.totals.kcal > 0 })
        #expect(dayWithBoth.weightKg == 62.4)
        #expect(dayWithBoth.totals.kcal == 330)
        // 只称重没吃饭的日子也要在,否则体重序列会断
        #expect(payload.days.contains { $0.weightKg == 63.0 && $0.totals.kcal == 0 })
        #expect(payload.profile.currentWeightKg == 62.4)
        #expect(payload.profile.goalWeightKg == 58)
    }

    @Test func payloadIncludesMeasuredVsProjectedWeightChange() throws {
        let payload = try buildPayload()
        // 实测变化与按摄入预测的变化都要给,AI 才能判断偏差在哪
        #expect(payload.summary.weightChangeKg != nil)
        #expect(payload.summary.projectedWeightChangeKg != nil)
    }

    @Test func deviceSourcedBurnIsLabelled() throws {
        let payload = try buildPayload()
        let strength = try #require(payload.days.compactMap(\.strength.first).first)
        // 来源必须带出去:device 误差可达 ±25%,不标注 AI 会当成精确值用
        #expect(strength.kcalBurned?.source == "device")
    }

    @Test func insufficientAdaptiveTdeeExportsNullWithReason() throws {
        let payload = try buildPayload(adaptive: .insufficientData(reason: "近 28 天还需 12 天记录"))
        #expect(payload.profile.measuredTdee == nil)
        #expect(payload.profile.measuredTdeeNote == "近 28 天还需 12 天记录")
    }

    @Test func unreliableAdaptiveTdeeIsNotExportedAsAValue() throws {
        let payload = try buildPayload(adaptive: .unreliable(kcal: 900, formulaKcal: 2000))
        // 不可信的值不能当成数字导出去,否则 AI 会照着它算
        #expect(payload.profile.measuredTdee == nil)
        #expect(payload.profile.measuredTdeeNote?.isEmpty == false)
    }

    @Test func availableAdaptiveTdeeIsExported() throws {
        let payload = try buildPayload(adaptive: .available(kcal: 2150, formulaKcal: 2000))
        #expect(payload.profile.measuredTdee == 2150)
        #expect(payload.profile.estimatedTdee == 2000)
    }

    @Test func encodesToValidJSON() throws {
        let payload = try buildPayload()
        let json = AIExportBuilder.encode(payload)
        let data = try #require(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["schemaVersion"] as? Int == 3)
        #expect(parsed?["days"] != nil)
    }
}
