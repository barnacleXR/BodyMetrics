import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

/// 写入层的行为。撤销是这里最容易出错的地方:删除会把空的 DayLog 一并回收,
/// 撤销时要能重新建起来
@MainActor
struct DayLogServiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    private func sampleDraft(name: String = "鸡胸肉") -> FoodDraft {
        FoodDraft(name: name, basis: .per100g, amount: 200,
                  kcal: 165, proteinG: 31, fatG: 3.6, carbG: 0)
    }

    private func fetchItems(_ context: ModelContext) throws -> [FoodItem] {
        try context.fetch(FetchDescriptor<FoodItem>())
    }

    private func fetchDayLogs(_ context: ModelContext) throws -> [DayLog] {
        try context.fetch(FetchDescriptor<DayLog>())
    }

    @Test func addingFoodCreatesDayLogAndMeal() throws {
        let context = try makeContext()
        DayLogService.addFood(sampleDraft(), mealType: .lunch, on: today, in: context)

        #expect(try fetchDayLogs(context).count == 1)
        #expect(try fetchItems(context).count == 1)
        let dayLog = try #require(DayLogService.fetchDayLog(for: today, in: context))
        #expect(dayLog.meals.count == 1)
        #expect(dayLog.meals.first?.type == .lunch)
    }

    @Test func addingTwoItemsToSameMealDoesNotCreateTwoMeals() throws {
        let context = try makeContext()
        DayLogService.addFood(sampleDraft(name: "鸡胸肉"), mealType: .lunch, on: today, in: context)
        DayLogService.addFood(sampleDraft(name: "米饭"), mealType: .lunch, on: today, in: context)

        let dayLog = try #require(DayLogService.fetchDayLog(for: today, in: context))
        #expect(dayLog.meals.count == 1)
        #expect(dayLog.meals.first?.items.count == 2)
    }

    @Test func deletingLastRecordRemovesTheEmptyDayLog() throws {
        let context = try makeContext()
        DayLogService.addFood(sampleDraft(), mealType: .lunch, on: today, in: context)
        let item = try #require(try fetchItems(context).first)

        DayLogService.deleteFood(item, in: context)

        #expect(try fetchItems(context).isEmpty)
        // 空壳 DayLog 要回收,否则日历上会留下一堆"有记录"的假标记
        #expect(try fetchDayLogs(context).isEmpty)
    }

    /// 撤销的核心用例:删掉当天唯一一条记录(连带 DayLog 被回收)后,
    /// 用快照重建必须能把记录放回去
    @Test func undoAfterDeletingLastRecordRestoresIt() throws {
        let context = try makeContext()
        let draft = sampleDraft()
        DayLogService.addFood(draft, mealType: .lunch, on: today, in: context)
        let item = try #require(try fetchItems(context).first)
        let snapshot = FoodDraft(from: item)

        DayLogService.deleteFood(item, in: context)
        DayLogService.addFood(snapshot, mealType: .lunch, on: today, in: context)

        let restored = try fetchItems(context)
        #expect(restored.count == 1)
        #expect(restored.first?.name == "鸡胸肉")
        #expect(restored.first?.amount == 200)

        let dayLogs = try fetchDayLogs(context)
        #expect(dayLogs.count == 1)
        #expect(dayLogs.first?.meals.first?.items.count == 1)
    }

    @Test func undoRestoresStrengthWorkoutWithItsSets() throws {
        let context = try makeContext()
        let draft = StrengthDraft(
            name: "深蹲",
            sets: [
                SetDraft(reps: 10, weightKg: 60, isWarmup: true),
                SetDraft(reps: 5, weightKg: 100, isWarmup: false),
            ]
        )
        DayLogService.addStrength(draft, on: today, in: context)
        let workout = try #require(try context.fetch(FetchDescriptor<StrengthWorkout>()).first)
        let snapshot = StrengthDraft(from: workout)

        DayLogService.deleteStrength(workout, in: context)
        #expect(try context.fetch(FetchDescriptor<StrengthWorkout>()).isEmpty)

        DayLogService.addStrength(snapshot, on: today, in: context)
        let restored = try #require(try context.fetch(FetchDescriptor<StrengthWorkout>()).first)
        #expect(restored.name == "深蹲")
        #expect(restored.sets.count == 2)
        #expect(restored.volumeKg == 500)   // 热身组不计
    }

    @Test func recordingFoodPutsItInThePresetLibrary() throws {
        let context = try makeContext()
        DayLogService.addFood(sampleDraft(), mealType: .lunch, on: today, in: context)
        DayLogService.addFood(sampleDraft(), mealType: .dinner, on: today, in: context)

        let presets = try context.fetch(FetchDescriptor<FoodPreset>())
        #expect(presets.count == 1)
        #expect(presets.first?.usageCount == 2)
    }

    @Test func editingFoodMovesItBetweenMealsWithoutLeavingEmptyOnes() throws {
        let context = try makeContext()
        DayLogService.addFood(sampleDraft(), mealType: .lunch, on: today, in: context)
        let item = try #require(try fetchItems(context).first)

        DayLogService.updateFood(item, with: sampleDraft(), mealType: .dinner, on: today, in: context)

        let dayLog = try #require(DayLogService.fetchDayLog(for: today, in: context))
        #expect(dayLog.meals.count == 1)
        #expect(dayLog.meals.first?.type == .dinner)
    }

    @Test func customExerciseIsRememberedButBuiltinsAreNot() throws {
        let context = try makeContext()
        DayLogService.addStrength(StrengthDraft(name: "卧推", sets: [SetDraft(reps: 5, weightKg: 60)]),
                                  on: today, in: context)
        DayLogService.addStrength(StrengthDraft(name: "保加利亚深蹲", sets: [SetDraft(reps: 8, weightKg: 40)]),
                                  on: today, in: context)

        let customs = try context.fetch(FetchDescriptor<CustomExercise>())
        // 内置库里已有的"卧推"不重复入库,只有新名字进自定义库
        #expect(customs.count == 1)
        #expect(customs.first?.name == "保加利亚深蹲")
    }

    @Test func repeatingACustomExerciseDoesNotDuplicateIt() throws {
        let context = try makeContext()
        for _ in 0..<3 {
            DayLogService.addStrength(StrengthDraft(name: "保加利亚深蹲", sets: [SetDraft(reps: 8, weightKg: 40)]),
                                      on: today, in: context)
        }
        // 谓词里比较枚举会静默失配,导致每记一次就多一条同名动作
        #expect(try context.fetch(FetchDescriptor<CustomExercise>()).count == 1)
    }

    @Test func sameNameWithDifferentBasisStaysTwoPresets() throws {
        let context = try makeContext()
        DayLogService.addFood(FoodDraft(name: "酸奶", basis: .per100g, amount: 100, kcal: 60,
                                        proteinG: 3, fatG: 2, carbG: 7),
                              mealType: .snack, on: today, in: context)
        DayLogService.addFood(FoodDraft(name: "酸奶", basis: .perServing, servingLabel: "盒", amount: 1,
                                        kcal: 120, proteinG: 6, fatG: 4, carbG: 14),
                              mealType: .snack, on: today, in: context)

        // 同名但基准不同是两种不同的记法,不能合并
        #expect(try context.fetch(FetchDescriptor<FoodPreset>()).count == 2)
    }
}
