import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

/// Markdown 导出。与 JSON 共用同一个 Payload,内容不能走偏,
/// 尤其是 device 来源标注与"实测代谢不可用"的原因说明
@MainActor
struct MarkdownExportRendererTests {

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
        adaptive: EnergyBalanceService.AdaptiveTDEE = .available(kcal: 2150, formulaKcal: 2000)
    ) throws -> AIExportBuilder.Payload {
        let context = try makeContext()
        let profile = UserProfile(goalWeight: 58, heightCm: 172, sex: .male,
                                  birthYear: 1995, activityLevel: .moderate, weeklyRateKg: -0.5)
        context.insert(profile)

        DayLogService.addFood(
            FoodDraft(name: "鸡胸肉", basis: .per100g, amount: 200,
                      kcal: 165, proteinG: 31, fatG: 3.6, carbG: 0),
            mealType: .lunch, on: day(-1), in: context
        )
        DayLogService.addStrength(
            StrengthDraft(name: "深蹲",
                          sets: [SetDraft(reps: 10, weightKg: 60, isWarmup: true),
                                 SetDraft(reps: 5, weightKg: 100),
                                 SetDraft(reps: 5, weightKg: 100)],
                          kcalBurned: 200, kcalSource: .device),
            on: day(-1), in: context
        )
        DayLogService.addCardio(
            CardioDraft(name: "跑步机", durationMin: 30, distanceKm: 5, kcalBurned: 300),
            on: day(-1), in: context
        )
        DayLogService.setNote("状态不错", on: day(-1), in: context)
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
            prompt: "请分析", calendar: calendar
        )
    }

    @Test func usesChineseMacroLabelsNotAbbreviations() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        #expect(markdown.contains("蛋白质"))
        #expect(markdown.contains("脂肪"))
        #expect(markdown.contains("碳水"))
    }

    @Test func containsWeightAndNutritionInOneTable() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        #expect(markdown.contains("## 每日汇总"))
        // 同一行里既有体重也有热量,这正是融合导出的意义
        #expect(markdown.contains("| 62.4 |"))
        #expect(markdown.contains("330"))
    }

    @Test func labelsDeviceSourcedBurn() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        // 不标注的话模型会把设备读数当成精确值参与能量平衡
        #expect(markdown.contains("设备读数"))
        #expect(markdown.contains("±25%"))
    }

    @Test func warmupSetsAreExcludedAndRepeatsCollapsed() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        // 两组相同的 5×100kg 合并,热身组不出现在组数里
        #expect(markdown.contains("2 组 × 5 × 100kg"))
        #expect(markdown.contains("容量 1000 kg"))
    }

    @Test func measuredMetabolismShowsDeltaAgainstFormula() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        #expect(markdown.contains("2150"))
        #expect(markdown.contains("+8%"))     // (2150 − 2000) / 2000
    }

    @Test func unavailableMeasuredMetabolismExplainsWhy() throws {
        let markdown = MarkdownExportRenderer.render(
            try buildPayload(adaptive: .insufficientData(reason: "近 28 天还需 12 天记录"))
        )
        // 留一个空字段会让模型自己猜,必须写清为什么没有
        #expect(markdown.contains("不可用"))
        #expect(markdown.contains("近 28 天还需 12 天记录"))
        #expect(!markdown.contains("实测代谢（由体重变化反推）"))
    }

    @Test func carriesBothActualAndProjectedWeightChange() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        #expect(markdown.contains("体重实际变化"))
        #expect(markdown.contains("按摄入预测"))
    }

    @Test func promptIsAppended() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        #expect(markdown.contains("## 分析请求"))
        #expect(markdown.contains("请分析"))
    }

    /// Markdown 版提示词不能提 JSON 字段名,否则模型会去找一个不存在的字段
    @Test func markdownPromptAvoidsJSONFieldNames() {
        let markdown = AIExportBuilder.prompt(singleDay: false, mentionsJSONFields: false)
        #expect(!markdown.contains("measuredTdee"))
        #expect(!markdown.contains("kcalBurned"))
        #expect(!markdown.contains("JSON"))
        #expect(markdown.contains("设备读数"))

        let json = AIExportBuilder.prompt(singleDay: false, mentionsJSONFields: true)
        #expect(json.contains("measuredTdee"))
        #expect(json.contains("kcalBurned"))
    }

    @Test func singleDayPromptDropsTheRangeQuestions() {
        let single = AIExportBuilder.prompt(singleDay: true, mentionsJSONFields: false)
        #expect(single.contains("三餐的蛋白质分配"))
        // 单日看不出体重趋势,不该问预测吻合与否
        #expect(!single.contains("按摄入预测"))
    }

    @Test func markdownIsSubstantiallySmallerThanJSON() throws {
        let payload = try buildPayload()
        let markdown = MarkdownExportRenderer.render(payload)
        let json = AIExportBuilder.encode(payload)
        // 省 token 是选 Markdown 的主要理由,回归时别把这条丢了
        #expect(markdown.utf8.count < json.utf8.count)
    }

    @Test func noteIsCarriedThrough() throws {
        let markdown = MarkdownExportRenderer.render(try buildPayload())
        #expect(markdown.contains("状态不错"))
    }
}
