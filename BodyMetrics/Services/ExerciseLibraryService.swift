import Foundation
import SwiftData

/// 动作库的读写。
///
/// 记录里存的是动作名字符串而非引用,所以改名必须连历史一起改写,
/// 否则同一个动作会在统计里裂成两条曲线,而界面上看不出为什么。
enum ExerciseLibraryService {

    /// 可选动作 = 自定义 + 未隐藏的内置。各表单统一走这里,避免各写一套
    static func options(
        kind: ExerciseKind,
        customExercises: [CustomExercise],
        hiddenBuiltinIDs: [String]
    ) -> [ExerciseCatalog.Entry] {
        let custom = customExercises
            .filter { $0.kind == kind }
            .map {
                ExerciseCatalog.Entry(
                    id: "custom-\($0.name)",
                    name: $0.name,
                    group: $0.group.isEmpty
                        ? (kind == .cardio ? ExerciseCatalog.cardioGroup : ExerciseCatalog.customGroup)
                        : $0.group
                )
            }
        let builtin = ExerciseCatalog.builtin(for: kind).filter { !hiddenBuiltinIDs.contains($0.id) }
        return custom + builtin
    }

    /// 重命名一个动作,并同步改写所有历史记录里的同名条目。
    /// 返回被改写的历史条数,供界面告知用户影响范围
    @discardableResult
    static func rename(
        from oldName: String,
        to newName: String,
        kind: ExerciseKind,
        in context: ModelContext
    ) -> Int {
        let old = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, old != new else { return 0 }

        // 自定义库里的那一条(内置动作改名等于建一个自定义别名)
        let customDescriptor = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.name == old })
        let customs = ((try? context.fetch(customDescriptor)) ?? []).filter { $0.kind == kind }
        if let existing = customs.first {
            existing.name = new
        } else if !ExerciseCatalog.builtin(for: kind).contains(where: { $0.name == new }) {
            // 改的是内置动作:把新名字存进自定义库,并隐藏原内置项由调用方处理
            context.insert(CustomExercise(
                name: new,
                kind: kind,
                group: kind == .cardio ? ExerciseCatalog.cardioGroup : ExerciseCatalog.customGroup
            ))
        }

        var touched = 0
        switch kind {
        case .strength:
            let descriptor = FetchDescriptor<StrengthWorkout>(predicate: #Predicate { $0.name == old })
            for workout in (try? context.fetch(descriptor)) ?? [] {
                workout.name = new
                touched += 1
            }
        case .cardio:
            let descriptor = FetchDescriptor<CardioSession>(predicate: #Predicate { $0.name == old })
            for session in (try? context.fetch(descriptor)) ?? [] {
                session.name = new
                touched += 1
            }
        }
        try? context.save()
        return touched
    }

    /// 删除一条自定义动作。历史记录不受影响——它们存的是名字,不是引用
    static func deleteCustom(_ exercise: CustomExercise, in context: ModelContext) {
        context.delete(exercise)
        try? context.save()
    }

    /// 隐藏/取消隐藏一个内置动作。只影响选择列表,不动历史
    static func toggleHidden(builtinID: String, profile: UserProfile, in context: ModelContext) {
        if let index = profile.hiddenBuiltinExerciseIDs.firstIndex(of: builtinID) {
            profile.hiddenBuiltinExerciseIDs.remove(at: index)
        } else {
            profile.hiddenBuiltinExerciseIDs.append(builtinID)
        }
        try? context.save()
    }

    /// 某个动作被用过多少次(用于删除前提示)
    static func usageCount(name: String, kind: ExerciseKind, in context: ModelContext) -> Int {
        switch kind {
        case .strength:
            let descriptor = FetchDescriptor<StrengthWorkout>(predicate: #Predicate { $0.name == name })
            return (try? context.fetchCount(descriptor)) ?? 0
        case .cardio:
            let descriptor = FetchDescriptor<CardioSession>(predicate: #Predicate { $0.name == name })
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }
}
