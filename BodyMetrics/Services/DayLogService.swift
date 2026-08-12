import Foundation
import SwiftData

/// 饮食与训练记录的写入层。
///
/// 集中在一处的原因:`DayLog` 是"一天一条"的聚合根,各个表单各写一套查找-创建逻辑
/// 迟早会写出同一天两条 DayLog。所有写入都必须经过这里。
enum DayLogService {

    // MARK: - 取与建

    static func fetchDayLog(for date: Date, in context: ModelContext, calendar: Calendar = .current) -> DayLog? {
        let dayStart = calendar.startOfDay(for: date)
        var descriptor = FetchDescriptor<DayLog>(predicate: #Predicate { $0.dayStart == dayStart })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// 找不到就建一条。写入前统一走这里,避免同一天出现两条 DayLog
    @discardableResult
    static func ensureDayLog(for date: Date, in context: ModelContext, calendar: Calendar = .current) -> DayLog {
        if let existing = fetchDayLog(for: date, in: context, calendar: calendar) { return existing }
        let created = DayLog(dayStart: calendar.startOfDay(for: date))
        context.insert(created)
        return created
    }

    /// 记录被删空后回收 DayLog,免得日历上留下一堆"有记录"的空壳。备注还在时保留
    static func pruneIfEmpty(_ dayLog: DayLog, in context: ModelContext) {
        guard dayLog.isEmpty, dayLog.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        context.delete(dayLog)
    }

    // MARK: - 饮食

    /// 往指定餐次加一条食物。同一餐次已存在时并进去,不新建第二条 Meal
    static func addFood(
        _ draft: FoodDraft,
        mealType: MealType,
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let dayLog = ensureDayLog(for: date, in: context, calendar: calendar)
        let item = draft.makeItem()
        context.insert(item)

        if let meal = dayLog.meals.first(where: { $0.type == mealType }) {
            meal.items.append(item)
        } else {
            let meal = Meal(type: mealType)
            context.insert(meal)
            meal.items = [item]
            dayLog.meals.append(meal)
        }
        upsertPreset(from: draft, in: context)
        try? context.save()
    }

    /// 改一条已有食物。可能被移到别的餐次,所以先从原餐摘掉再按目标餐次放回
    static func updateFood(
        _ item: FoodItem,
        with draft: FoodDraft,
        mealType: MealType,
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let dayLog = ensureDayLog(for: date, in: context, calendar: calendar)
        draft.apply(to: item)

        if item.meal?.type != mealType {
            item.meal?.items.removeAll { $0.id == item.id }
            if let target = dayLog.meals.first(where: { $0.type == mealType }) {
                target.items.append(item)
            } else {
                let meal = Meal(type: mealType)
                context.insert(meal)
                meal.items = [item]
                dayLog.meals.append(meal)
            }
        }
        removeEmptyMeals(in: dayLog, context: context)
        upsertPreset(from: draft, in: context)
        try? context.save()
    }

    static func deleteFood(_ item: FoodItem, in context: ModelContext) {
        let meal = item.meal
        let dayLog = meal?.dayLog
        meal?.items.removeAll { $0.id == item.id }
        context.delete(item)
        if let dayLog {
            removeEmptyMeals(in: dayLog, context: context)
            pruneIfEmpty(dayLog, in: context)
        }
        try? context.save()
    }

    private static func removeEmptyMeals(in dayLog: DayLog, context: ModelContext) {
        let empties = dayLog.meals.filter { $0.items.isEmpty }
        for meal in empties {
            dayLog.meals.removeAll { $0.id == meal.id }
            context.delete(meal)
        }
    }

    // MARK: - 常用食物库

    /// 记录过的食物自动入库并累加使用次数,下次录入直接搜得到。
    /// 同名同基准视为同一条;营养值以最近一次录入为准(存量记录是快照,不受影响)
    static func upsertPreset(from draft: FoodDraft, in context: ModelContext) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        // 只按名称建谓词,基准放到 Swift 层比。#Predicate 里比较自定义 Codable 枚举
        // 会静默匹配不上,导致同一条食物每记一次就在库里多堆一条重复项
        let descriptor = FetchDescriptor<FoodPreset>(predicate: #Predicate { $0.name == name })
        let sameBasis = (try? context.fetch(descriptor))?.first { $0.basis == draft.basis }
        if let existing = sameBasis {
            existing.kcal = draft.kcal
            existing.proteinG = draft.proteinG
            existing.fatG = draft.fatG
            existing.carbG = draft.carbG
            existing.servingLabel = draft.servingLabel
            existing.usageCount += 1
            existing.lastUsedAt = .now
        } else {
            let preset = FoodPreset(
                name: name, basis: draft.basis, servingLabel: draft.servingLabel,
                kcal: draft.kcal, proteinG: draft.proteinG, fatG: draft.fatG, carbG: draft.carbG,
                usageCount: 1, lastUsedAt: .now
            )
            context.insert(preset)
        }
    }

    // MARK: - 力量与有氧

    static func addStrength(
        _ draft: StrengthDraft,
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let dayLog = ensureDayLog(for: date, in: context, calendar: calendar)
        let workout = draft.makeWorkout(sortIndex: dayLog.strength.count)
        context.insert(workout)
        for set in workout.sets { context.insert(set) }
        dayLog.strength.append(workout)
        ensureCustomExercise(named: draft.name, kind: .strength, in: context)
        try? context.save()
    }

    static func updateStrength(_ workout: StrengthWorkout, with draft: StrengthDraft, in context: ModelContext) {
        for set in workout.sets { context.delete(set) }
        workout.sets = []
        draft.apply(to: workout)
        for set in workout.sets { context.insert(set) }
        ensureCustomExercise(named: draft.name, kind: .strength, in: context)
        try? context.save()
    }

    static func deleteStrength(_ workout: StrengthWorkout, in context: ModelContext) {
        let dayLog = workout.dayLog
        dayLog?.strength.removeAll { $0.id == workout.id }
        context.delete(workout)
        if let dayLog { pruneIfEmpty(dayLog, in: context) }
        try? context.save()
    }

    static func addCardio(
        _ draft: CardioDraft,
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        let dayLog = ensureDayLog(for: date, in: context, calendar: calendar)
        let session = draft.makeSession(sortIndex: dayLog.cardio.count)
        context.insert(session)
        dayLog.cardio.append(session)
        ensureCustomExercise(named: draft.name, kind: .cardio, in: context)
        try? context.save()
    }

    static func updateCardio(_ session: CardioSession, with draft: CardioDraft, in context: ModelContext) {
        draft.apply(to: session)
        ensureCustomExercise(named: draft.name, kind: .cardio, in: context)
        try? context.save()
    }

    static func deleteCardio(_ session: CardioSession, in context: ModelContext) {
        let dayLog = session.dayLog
        dayLog?.cardio.removeAll { $0.id == session.id }
        context.delete(session)
        if let dayLog { pruneIfEmpty(dayLog, in: context) }
        try? context.save()
    }

    // MARK: - 动作库

    /// 录入一个库里没有的动作名时自动入库,否则下次搜不到、得重打全名
    static func ensureCustomExercise(named name: String, kind: ExerciseKind, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !ExerciseCatalog.builtin(for: kind).contains(where: { $0.name == trimmed }) else { return }
        // 同上:kind 放到 Swift 层比,不进谓词
        let descriptor = FetchDescriptor<CustomExercise>(predicate: #Predicate { $0.name == trimmed })
        let existing = (try? context.fetch(descriptor))?.first { $0.kind == kind }
        guard existing == nil else { return }
        context.insert(CustomExercise(
            name: trimmed,
            kind: kind,
            group: kind == .cardio ? ExerciseCatalog.cardioGroup : ExerciseCatalog.customGroup
        ))
    }

    // MARK: - 备注

    static func setNote(_ note: String, on date: Date, in context: ModelContext, calendar: Calendar = .current) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // 备注被清空且当天没有任何记录时不留空壳
        if trimmed.isEmpty, let existing = fetchDayLog(for: date, in: context, calendar: calendar) {
            existing.note = ""
            pruneIfEmpty(existing, in: context)
            try? context.save()
            return
        }
        guard !trimmed.isEmpty else { return }
        let dayLog = ensureDayLog(for: date, in: context, calendar: calendar)
        dayLog.note = note
        try? context.save()
    }
}
