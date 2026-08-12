import Testing
import Foundation
import SwiftData
@testable import BodyMetrics

/// 迁移安全:加在**已存在模型**上的枚举/数组字段必须用可空原始值存储。
///
/// SwiftData 的轻量迁移只给旧表加列,不回填默认值。老用户那一行的新列是 NULL,
/// 非可选的 Codable 枚举属性一读就 "Could not cast Optional<Any>" 崩溃——
/// 而且是一开 App 就崩,数据还在但进不去。
@MainActor
struct MigrationSafetyTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func profileEnumsFallBackWhenStorageIsEmpty() throws {
        let context = try makeContext()
        let profile = UserProfile()
        context.insert(profile)
        // 模拟迁移后的旧行:新列全是 NULL
        profile.sexRaw = nil
        profile.activityLevelRaw = nil
        profile.themePreferenceRaw = nil
        profile.hiddenExerciseIDsRaw = nil
        try context.save()

        // 读取不能崩,且要落到合理的默认值
        #expect(profile.sex == .male)
        #expect(profile.activityLevel == .sedentary)
        #expect(profile.themePreference == .system)
        #expect(profile.hiddenBuiltinExerciseIDs.isEmpty)
    }

    @Test func reminderKindFallsBackWhenStorageIsEmpty() throws {
        let context = try makeContext()
        let reminder = Reminder(hour: 8, minute: 0)
        context.insert(reminder)
        reminder.kindRaw = nil
        try context.save()

        #expect(reminder.kind == .weighIn)
    }

    @Test func writingThroughComputedPropertiesPersists() throws {
        let context = try makeContext()
        let profile = UserProfile()
        context.insert(profile)

        profile.sex = .female
        profile.activityLevel = .active
        profile.themePreference = .dark
        profile.hiddenBuiltinExerciseIDs = ["bench-press"]
        try context.save()

        #expect(profile.sexRaw == "female")
        #expect(profile.activityLevelRaw == "active")
        #expect(profile.themePreferenceRaw == "dark")
        #expect(profile.hiddenExerciseIDsRaw == ["bench-press"])
        #expect(profile.sex == .female)
        #expect(profile.hiddenBuiltinExerciseIDs == ["bench-press"])
    }

    @Test func unknownRawValueFallsBackInsteadOfCrashing() throws {
        let context = try makeContext()
        let profile = UserProfile()
        context.insert(profile)
        // 未来版本写入的、当前版本不认识的值(降级安装)
        profile.themePreferenceRaw = "solarized"
        try context.save()

        #expect(profile.themePreference == .system)
    }
}
