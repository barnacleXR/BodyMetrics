import Foundation
import SwiftData

/// 完整备份的导出与导入。
///
/// 导入同时兼容两种文件:本 App 的完整备份,以及 HTML 原型导出的
/// `dietlog.v1`(schemaVersion 3)。原型的字段名在这里必须严格对齐,
/// 改名就等于把老数据挡在门外。
enum BackupService {

    static let formatVersion = 1

    // MARK: - 备份格式

    struct Backup: Codable {
        var formatVersion: Int
        var exportedAt: String
        var profile: ProfileData?
        var targets: [TargetData]
        var weightEntries: [EntryData]
        var days: [DayData]
        var foodPresets: [PresetData]
        var customExercises: [ExerciseData]
        var reminders: [ReminderData]

        struct ProfileData: Codable {
            var goalWeight: Double
            var heightCm: Double
            var sex: String
            var birthYear: Int
            var activityLevel: String
            var weeklyRateKg: Double
            var addBurnedToBudget: Bool
            var useAdaptiveTDEE: Bool
            var themePreference: String
            var hiddenBuiltinExerciseIDs: [String]
            var reminderEnabled: Bool
            var biometricLockEnabled: Bool
        }

        struct TargetData: Codable {
            var effectiveFrom: String
            var kcal: Double
            var proteinG: Double
            var fatG: Double
            var carbG: Double
        }

        struct EntryData: Codable {
            var metric: String
            var value: Double
            var date: String
        }

        struct DayData: Codable {
            var date: String
            var note: String
            var meals: [MealData]
            var strength: [StrengthData]
            var cardio: [CardioData]

            struct MealData: Codable {
                var type: String
                var items: [ItemData]

                struct ItemData: Codable {
                    var name: String
                    var basis: String
                    var servingLabel: String
                    var amount: Double
                    var kcal: Double
                    var proteinG: Double
                    var fatG: Double
                    var carbG: Double
                }
            }

            struct StrengthData: Codable {
                var name: String
                var kcalBurned: Double
                var kcalSource: String
                var sets: [SetData]

                struct SetData: Codable {
                    var reps: Int
                    var weightKg: Double
                    var isWarmup: Bool
                }
            }

            struct CardioData: Codable {
                var name: String
                var durationMin: Double
                var distanceKm: Double?
                var kcalBurned: Double
                var kcalSource: String
            }
        }

        struct PresetData: Codable {
            var name: String
            var basis: String
            var servingLabel: String
            var kcal: Double
            var proteinG: Double
            var fatG: Double
            var carbG: Double
            var usageCount: Int
        }

        struct ExerciseData: Codable {
            var name: String
            var kind: String
            var group: String
        }

        struct ReminderData: Codable {
            var hour: Int
            var minute: Int
            var kind: String
        }
    }

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    // MARK: - 导出

    static func exportJSON(from context: ModelContext, calendar: Calendar = .current) -> String {
        let formatter = dayFormatter
        let iso = ISO8601DateFormatter()

        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        let targets = (try? context.fetch(FetchDescriptor<NutritionTarget>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<MetricEntry>())) ?? []
        let dayLogs = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        let presets = (try? context.fetch(FetchDescriptor<FoodPreset>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []

        let backup = Backup(
            formatVersion: formatVersion,
            exportedAt: iso.string(from: .now),
            profile: profile.map {
                .init(
                    goalWeight: $0.goalWeight, heightCm: $0.heightCm,
                    sex: $0.sex.rawValue, birthYear: $0.birthYear,
                    activityLevel: $0.activityLevel.rawValue, weeklyRateKg: $0.weeklyRateKg,
                    addBurnedToBudget: $0.addBurnedToBudget, useAdaptiveTDEE: $0.useAdaptiveTDEE,
                    themePreference: $0.themePreference.rawValue,
                    hiddenBuiltinExerciseIDs: $0.hiddenBuiltinExerciseIDs,
                    reminderEnabled: $0.reminderEnabled, biometricLockEnabled: $0.biometricLockEnabled
                )
            },
            targets: targets.map {
                .init(effectiveFrom: formatter.string(from: $0.effectiveFrom), kcal: $0.kcal,
                      proteinG: $0.proteinG, fatG: $0.fatG, carbG: $0.carbG)
            },
            weightEntries: entries.map {
                .init(metric: $0.metric.rawValue, value: $0.value, date: iso.string(from: $0.date))
            },
            days: dayLogs.map { log in
                .init(
                    date: formatter.string(from: log.dayStart),
                    note: log.note,
                    meals: log.sortedMeals.map { meal in
                        .init(type: meal.type.rawValue, items: meal.items.map {
                            .init(name: $0.name, basis: $0.basis.rawValue, servingLabel: $0.servingLabel,
                                  amount: $0.amount, kcal: $0.kcal, proteinG: $0.proteinG,
                                  fatG: $0.fatG, carbG: $0.carbG)
                        })
                    },
                    strength: log.strength.sorted { $0.sortIndex < $1.sortIndex }.map { workout in
                        .init(name: workout.name, kcalBurned: workout.kcalBurned,
                              kcalSource: workout.kcalSource.rawValue,
                              sets: workout.orderedSets.map {
                                  .init(reps: $0.reps, weightKg: $0.weightKg, isWarmup: $0.isWarmup)
                              })
                    },
                    cardio: log.cardio.sorted { $0.sortIndex < $1.sortIndex }.map {
                        .init(name: $0.name, durationMin: $0.durationMin, distanceKm: $0.distanceKm,
                              kcalBurned: $0.kcalBurned, kcalSource: $0.kcalSource.rawValue)
                    }
                )
            },
            foodPresets: presets.map {
                .init(name: $0.name, basis: $0.basis.rawValue, servingLabel: $0.servingLabel,
                      kcal: $0.kcal, proteinG: $0.proteinG, fatG: $0.fatG, carbG: $0.carbG,
                      usageCount: $0.usageCount)
            },
            customExercises: exercises.map {
                .init(name: $0.name, kind: $0.kind.rawValue, group: $0.group)
            },
            reminders: reminders.map {
                .init(hour: $0.hour, minute: $0.minute, kind: $0.kind.rawValue)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(backup), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    // MARK: - 导入

    enum ImportResult {
        case restored(days: Int, entries: Int)
        case prototypeSummaryOnly(days: Int)
        case failed(String)
    }

    /// 导入前先清空,避免和现有数据混成两份互相矛盾的记录
    static func importJSON(_ text: String, into context: ModelContext, calendar: Calendar = .current) -> ImportResult {
        guard let data = text.data(using: .utf8) else {
            return .failed(String(localized: "文件不是有效的文本"))
        }
        let decoder = JSONDecoder()

        if let backup = try? decoder.decode(Backup.self, from: data) {
            wipe(context)
            restore(backup, into: context, calendar: calendar)
            return .restored(days: backup.days.count, entries: backup.weightEntries.count)
        }

        // 退回原型格式:分析包只含汇总,恢复不了逐条记录
        if let prototype = try? decoder.decode(PrototypeExport.self, from: data) {
            let restored = restorePrototype(prototype, into: context, calendar: calendar)
            return .prototypeSummaryOnly(days: restored)
        }

        return .failed(String(localized: "无法识别的备份格式"))
    }

    static func wipe(_ context: ModelContext) {
        for log in (try? context.fetch(FetchDescriptor<DayLog>())) ?? [] { context.delete(log) }
        for entry in (try? context.fetch(FetchDescriptor<MetricEntry>())) ?? [] { context.delete(entry) }
        for target in (try? context.fetch(FetchDescriptor<NutritionTarget>())) ?? [] { context.delete(target) }
        for preset in (try? context.fetch(FetchDescriptor<FoodPreset>())) ?? [] { context.delete(preset) }
        for exercise in (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [] { context.delete(exercise) }
        for report in (try? context.fetch(FetchDescriptor<AIReport>())) ?? [] { context.delete(report) }
        try? context.save()
    }

    private static func restore(_ backup: Backup, into context: ModelContext, calendar: Calendar) {
        let formatter = dayFormatter
        let iso = ISO8601DateFormatter()

        if let data = backup.profile {
            let profile = (try? context.fetch(FetchDescriptor<UserProfile>()).first) ?? {
                let created = UserProfile()
                context.insert(created)
                return created
            }()
            profile.goalWeight = data.goalWeight
            profile.heightCm = data.heightCm
            profile.sex = Sex(rawValue: data.sex) ?? .male
            profile.birthYear = data.birthYear
            profile.activityLevel = ActivityLevel(rawValue: data.activityLevel) ?? .sedentary
            profile.weeklyRateKg = data.weeklyRateKg
            profile.addBurnedToBudget = data.addBurnedToBudget
            profile.useAdaptiveTDEE = data.useAdaptiveTDEE
            profile.themePreference = ThemePreference(rawValue: data.themePreference) ?? .system
            profile.hiddenBuiltinExerciseIDs = data.hiddenBuiltinExerciseIDs
            profile.reminderEnabled = data.reminderEnabled
            profile.biometricLockEnabled = data.biometricLockEnabled
        }

        for target in backup.targets {
            guard let date = formatter.date(from: target.effectiveFrom) else { continue }
            context.insert(NutritionTarget(
                effectiveFrom: calendar.startOfDay(for: date), kcal: target.kcal,
                proteinG: target.proteinG, fatG: target.fatG, carbG: target.carbG
            ))
        }

        for entry in backup.weightEntries {
            guard let date = iso.date(from: entry.date),
                  let metric = Metric(rawValue: entry.metric) else { continue }
            context.insert(MetricEntry(metric: metric, value: entry.value, date: date))
        }

        for day in backup.days {
            guard let date = formatter.date(from: day.date) else { continue }
            let log = DayLog(dayStart: calendar.startOfDay(for: date), note: day.note)
            context.insert(log)

            for mealData in day.meals {
                let meal = Meal(type: MealType(rawValue: mealData.type) ?? .snack)
                context.insert(meal)
                meal.items = mealData.items.map {
                    let item = FoodItem(
                        name: $0.name, basis: FoodBasis(rawValue: $0.basis) ?? .per100g,
                        servingLabel: $0.servingLabel, amount: $0.amount,
                        kcal: $0.kcal, proteinG: $0.proteinG, fatG: $0.fatG, carbG: $0.carbG
                    )
                    context.insert(item)
                    return item
                }
                log.meals.append(meal)
            }

            for (index, workoutData) in day.strength.enumerated() {
                let workout = StrengthWorkout(
                    name: workoutData.name, kcalBurned: workoutData.kcalBurned,
                    kcalSource: KcalSource(rawValue: workoutData.kcalSource) ?? .manual,
                    sortIndex: index
                )
                context.insert(workout)
                workout.sets = workoutData.sets.enumerated().map { setIndex, setData in
                    let set = StrengthSet(reps: setData.reps, weightKg: setData.weightKg,
                                          isWarmup: setData.isWarmup, sortIndex: setIndex)
                    context.insert(set)
                    return set
                }
                log.strength.append(workout)
            }

            for (index, cardioData) in day.cardio.enumerated() {
                let session = CardioSession(
                    name: cardioData.name, durationMin: cardioData.durationMin,
                    distanceKm: cardioData.distanceKm, kcalBurned: cardioData.kcalBurned,
                    kcalSource: KcalSource(rawValue: cardioData.kcalSource) ?? .manual,
                    sortIndex: index
                )
                context.insert(session)
                log.cardio.append(session)
            }
        }

        for preset in backup.foodPresets {
            context.insert(FoodPreset(
                name: preset.name, basis: FoodBasis(rawValue: preset.basis) ?? .per100g,
                servingLabel: preset.servingLabel, kcal: preset.kcal, proteinG: preset.proteinG,
                fatG: preset.fatG, carbG: preset.carbG, usageCount: preset.usageCount
            ))
        }

        for exercise in backup.customExercises {
            context.insert(CustomExercise(
                name: exercise.name,
                kind: ExerciseKind(rawValue: exercise.kind) ?? .strength,
                group: exercise.group
            ))
        }

        try? context.save()
    }

    // MARK: - 原型格式(schemaVersion 3)

    /// HTML 原型导出的分析包。字段名必须与原型一致
    private struct PrototypeExport: Decodable {
        var schemaVersion: Int
        var days: [PrototypeDay]

        struct PrototypeDay: Decodable {
            var date: String
            var note: String?
        }
    }

    /// 原型的分析包只含汇总,恢复不了逐条记录——只把日期与备注放回去,
    /// 并在界面上照实说明,不假装完整恢复
    private static func restorePrototype(
        _ export: PrototypeExport,
        into context: ModelContext,
        calendar: Calendar
    ) -> Int {
        let formatter = dayFormatter
        var restored = 0
        for day in export.days {
            guard let date = formatter.date(from: day.date) else { continue }
            let note = day.note ?? ""
            guard !note.isEmpty else { continue }
            DayLogService.setNote(note, on: calendar.startOfDay(for: date), in: context, calendar: calendar)
            restored += 1
        }
        return restored
    }
}
