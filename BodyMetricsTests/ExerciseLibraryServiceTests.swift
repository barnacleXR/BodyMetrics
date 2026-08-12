import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

@MainActor
struct ExerciseLibraryServiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    /// 改名不同步历史的话,统计里同一个动作会裂成两条曲线
    @Test func renamingRewritesHistoricalRecords() throws {
        let context = try makeContext()
        for _ in 0..<3 {
            DayLogService.addStrength(
                StrengthDraft(name: "保加利亚深蹲", sets: [SetDraft(reps: 8, weightKg: 40)]),
                on: today, in: context
            )
        }

        let touched = ExerciseLibraryService.rename(
            from: "保加利亚深蹲", to: "保加利亚分腿蹲", kind: .strength, in: context
        )

        #expect(touched == 3)
        let workouts = try context.fetch(FetchDescriptor<StrengthWorkout>())
        #expect(workouts.allSatisfy { $0.name == "保加利亚分腿蹲" })
        // 库里那一条也要跟着改,否则下次搜旧名字还在
        let customs = try context.fetch(FetchDescriptor<CustomExercise>())
        #expect(customs.count == 1)
        #expect(customs.first?.name == "保加利亚分腿蹲")
    }

    @Test func renamingCardioRewritesItsOwnRecordsOnly() throws {
        let context = try makeContext()
        DayLogService.addCardio(CardioDraft(name: "爬楼机", durationMin: 20), on: today, in: context)
        DayLogService.addStrength(StrengthDraft(name: "爬楼机", sets: [SetDraft(reps: 5, weightKg: 10)]),
                                  on: today, in: context)

        ExerciseLibraryService.rename(from: "爬楼机", to: "登山机", kind: .cardio, in: context)

        let cardio = try context.fetch(FetchDescriptor<CardioSession>())
        let strength = try context.fetch(FetchDescriptor<StrengthWorkout>())
        #expect(cardio.first?.name == "登山机")
        // 同名的力量记录不该被改到
        #expect(strength.first?.name == "爬楼机")
    }

    @Test func renamingToBlankOrSameNameIsANoop() throws {
        let context = try makeContext()
        DayLogService.addStrength(StrengthDraft(name: "自创动作", sets: [SetDraft(reps: 5, weightKg: 10)]),
                                  on: today, in: context)

        #expect(ExerciseLibraryService.rename(from: "自创动作", to: "  ", kind: .strength, in: context) == 0)
        #expect(ExerciseLibraryService.rename(from: "自创动作", to: "自创动作", kind: .strength, in: context) == 0)
        let workouts = try context.fetch(FetchDescriptor<StrengthWorkout>())
        #expect(workouts.first?.name == "自创动作")
    }

    @Test func deletingCustomExerciseLeavesHistoryIntact() throws {
        let context = try makeContext()
        DayLogService.addStrength(StrengthDraft(name: "自创动作", sets: [SetDraft(reps: 5, weightKg: 10)]),
                                  on: today, in: context)
        let custom = try #require(try context.fetch(FetchDescriptor<CustomExercise>()).first)

        ExerciseLibraryService.deleteCustom(custom, in: context)

        #expect(try context.fetch(FetchDescriptor<CustomExercise>()).isEmpty)
        // 记录存的是名字不是引用,删库不该动历史
        #expect(try context.fetch(FetchDescriptor<StrengthWorkout>()).count == 1)
    }

    @Test func hiddenBuiltinsDropOutOfTheOptionList() throws {
        let all = ExerciseLibraryService.options(kind: .strength, customExercises: [], hiddenBuiltinIDs: [])
        let hidden = ExerciseLibraryService.options(
            kind: .strength, customExercises: [], hiddenBuiltinIDs: ["bench-press"]
        )
        #expect(all.count == ExerciseCatalog.strength.count)
        #expect(hidden.count == all.count - 1)
        #expect(!hidden.contains { $0.id == "bench-press" })
    }

    @Test func customExercisesComeBeforeBuiltins() throws {
        let custom = CustomExercise(name: "自创动作", kind: .strength, group: "自定义")
        let options = ExerciseLibraryService.options(
            kind: .strength, customExercises: [custom], hiddenBuiltinIDs: []
        )
        #expect(options.first?.name == "自创动作")
    }

    @Test func usageCountReportsHowOftenAnExerciseWasLogged() throws {
        let context = try makeContext()
        for _ in 0..<2 {
            DayLogService.addStrength(StrengthDraft(name: "深蹲", sets: [SetDraft(reps: 5, weightKg: 100)]),
                                      on: today, in: context)
        }
        #expect(ExerciseLibraryService.usageCount(name: "深蹲", kind: .strength, in: context) == 2)
        #expect(ExerciseLibraryService.usageCount(name: "硬拉", kind: .strength, in: context) == 0)
    }
}
