import Foundation

/// 导出给 AI 分析的数据包。
///
/// 与原型的 schemaVersion 3 字段名保持一致(便于互相导入),但**多带了体重序列
/// 与能量收支结论**——这正是融合之后才有的东西:AI 能看到"吃了多少"与"体重
/// 怎么响应"两边,才谈得上给有依据的建议。
enum AIExportBuilder {

    static let schemaVersion = 3

    /// 提示词跟着导出格式走:JSON 版可以直呼字段名,Markdown 版必须用中文说法,
    /// 否则会让模型去找一个根本不存在的 `measuredTdee` 字段
    static func prompt(singleDay: Bool, mentionsJSONFields: Bool) -> String {
        let burnNote = mentionsJSONFields
            ? String(localized: "注意:kcalBurned 的 source 若为 device,误差可达 ±25%,请勿当作精确值参与能量平衡计算。")
            : String(localized: "注意:标注「设备读数」的消耗误差可达 ±25%,请勿当作精确值参与能量平衡计算。")

        if singleDay {
            let head = mentionsJSONFields
                ? String(localized: "以下是我某一天的饮食与训练记录(JSON)。请分析:")
                : String(localized: "以下是我某一天的饮食与训练记录。请分析:")
            return """
                \(head)
                \(String(localized: "1. 这一天的热量与三大宏量相对目标的缺口,指出偏差最大的项"))
                \(String(localized: "2. 三餐的蛋白质分配是否合理"))
                \(String(localized: "3. 如果还没吃完,建议接下来吃什么能补齐缺口"))
                \(String(localized: "4. 指出这一天最值得改的一个点"))
                \(burnNote)
                """
        }

        let head = mentionsJSONFields
            ? String(localized: "以下是我的饮食、训练与体重数据(JSON)。请分析:")
            : String(localized: "以下是我的饮食、训练与体重记录。请分析:")
        let metabolismLine = mentionsJSONFields
            ? String(localized: "3. 实测代谢(measuredTdee)与公式估算(estimatedTdee)的差异说明了什么")
            : String(localized: "3. 实测代谢与公式估算 TDEE 的差异说明了什么")
        return """
            \(head)
            \(String(localized: "1. 热量与三大宏量的达成情况,指出偏差最大的项"))
            \(String(localized: "2. 蛋白质摄入是否足够支撑训练量"))
            \(metabolismLine)
            \(String(localized: "4. 体重的实际变化与按摄入预测的变化是否吻合,不吻合可能是什么原因"))
            \(String(localized: "5. 给出 3 条具体可执行的调整建议"))
            \(burnNote)
            """
    }

    /// 全部四种组合,用于判断用户是否改过提示词
    static var allDefaultPrompts: [String] {
        [
            prompt(singleDay: false, mentionsJSONFields: false),
            prompt(singleDay: false, mentionsJSONFields: true),
            prompt(singleDay: true, mentionsJSONFields: false),
            prompt(singleDay: true, mentionsJSONFields: true),
        ]
    }

    // MARK: - Payload

    struct Payload: Encodable {
        var schemaVersion: Int
        var exportedAt: String
        var timezone: String
        var range: Range
        var profile: Profile
        var settings: Settings
        var summary: Summary
        var days: [Day]
        var analysisPrompt: String

        struct Range: Encodable {
            var from: String
            var to: String
            var daysWithData: Int
        }

        struct Profile: Encodable {
            var sex: String
            var age: Int?
            var heightCm: Double
            var currentWeightKg: Double?
            var goalWeightKg: Double
            var weeklyRateKg: Double
            var activityLevel: String
            var estimatedTdee: Double
            /// 由实测体重反推的真实代谢;数据不足时为 null,并在 note 里说明
            var measuredTdee: Double?
            var measuredTdeeNote: String?
        }

        struct Settings: Encodable {
            var burnedCaloriesAddedToBudget: Bool
            var usingMeasuredTdee: Bool
        }

        struct Summary: Encodable {
            var avgKcal: Int
            var avgProteinG: Double
            var kcalWithin10PctOfTargetDays: Int
            var checkInStreak: Int
            var weightChangeKg: Double?
            var projectedWeightChangeKg: Double?
        }

        struct Day: Encodable {
            var date: String
            var weightKg: Double?
            var target: Target?
            var totals: Totals
            var meals: [Meal]
            var strength: [Strength]
            var cardio: [Cardio]
            var note: String

            struct Target: Encodable {
                var kcal: Double
                var proteinG: Double
                var fatG: Double
                var carbG: Double
            }

            struct Totals: Encodable {
                var kcal: Int
                var proteinG: Double
                var fatG: Double
                var carbG: Double
                var kcalBurned: Int
                var trainingVolumeKg: Int
            }

            struct Meal: Encodable {
                var type: String
                var items: [Item]

                struct Item: Encodable {
                    var name: String
                    var amount: Double
                    var unit: String
                    var kcal: Int
                    var proteinG: Double
                    var fatG: Double
                    var carbG: Double
                }
            }

            struct Strength: Encodable {
                var exercise: String
                var sets: [Set]
                var volumeKg: Int
                var estimated1rmKg: Int
                var kcalBurned: Burn?

                struct Set: Encodable {
                    var reps: Int
                    var weightKg: Double
                    var warmup: Bool
                }
            }

            struct Cardio: Encodable {
                var exercise: String
                var durationMin: Double
                var distanceKm: Double?
                var kcalBurned: Burn
            }

            struct Burn: Encodable {
                var value: Double
                var source: String
            }
        }
    }

    // MARK: - 构建

    static func build(
        days fusedDays: [FusedDay],
        dayLogs: [DayLog],
        entries: [MetricEntry],
        targets: [NutritionTarget],
        profile: UserProfile?,
        adaptive: EnergyBalanceService.AdaptiveTDEE,
        formulaTDEE: Double,
        prompt: String,
        calendar: Calendar = .current
    ) -> Payload {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let logsByDay = Dictionary(
            dayLogs.map { (calendar.startOfDay(for: $0.dayStart), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let withData = fusedDays.filter { $0.hasAnyRecord }
        let logged = fusedDays.filter(\.hasIntakeRecord)

        var exportedDays: [Payload.Day] = []
        for fused in withData {
            let log = logsByDay[fused.date]
            let totals = log.map { NutritionCalculator.totals(for: $0) } ?? .zero
            let target = NutritionCalculator.target(on: fused.date, in: targets, calendar: calendar)

            exportedDays.append(Payload.Day(
                date: dayFormatter.string(from: fused.date),
                weightKg: fused.weight,
                target: target.map {
                    .init(kcal: $0.kcal, proteinG: $0.proteinG, fatG: $0.fatG, carbG: $0.carbG)
                },
                totals: .init(
                    kcal: Int(totals.macros.kcal.rounded()),
                    proteinG: NutritionCalculator.round1(totals.macros.proteinG),
                    fatG: NutritionCalculator.round1(totals.macros.fatG),
                    carbG: NutritionCalculator.round1(totals.macros.carbG),
                    kcalBurned: Int(totals.burnedKcal.rounded()),
                    trainingVolumeKg: Int(totals.volumeKg)
                ),
                meals: (log?.sortedMeals ?? []).map { meal in
                    .init(
                        type: meal.type.rawValue,
                        items: meal.items.map { item in
                            let scaled = item.scaled
                            return .init(
                                name: item.name,
                                amount: item.amount,
                                unit: item.basis == .per100g
                                    ? "g"
                                    : (item.servingLabel.isEmpty ? "serving" : item.servingLabel),
                                kcal: Int(scaled.kcal.rounded()),
                                proteinG: NutritionCalculator.round1(scaled.proteinG),
                                fatG: NutritionCalculator.round1(scaled.fatG),
                                carbG: NutritionCalculator.round1(scaled.carbG)
                            )
                        }
                    )
                },
                strength: (log?.strength ?? []).sorted { $0.sortIndex < $1.sortIndex }.map { workout in
                    .init(
                        exercise: workout.name,
                        sets: workout.orderedSets.map {
                            .init(reps: $0.reps, weightKg: $0.weightKg, warmup: $0.isWarmup)
                        },
                        volumeKg: Int(workout.volumeKg),
                        estimated1rmKg: Int(workout.bestE1RM),
                        kcalBurned: workout.kcalBurned > 0
                            ? .init(value: workout.kcalBurned, source: workout.kcalSource.rawValue)
                            : nil
                    )
                },
                cardio: (log?.cardio ?? []).sorted { $0.sortIndex < $1.sortIndex }.map { session in
                    .init(
                        exercise: session.name,
                        durationMin: session.durationMin,
                        distanceKm: session.distanceKm,
                        kcalBurned: .init(value: session.kcalBurned, source: session.kcalSource.rawValue)
                    )
                },
                note: log?.note ?? ""
            ))
        }

        // 体重实际变化 vs 按摄入预测的变化——两边一起给,AI 才能判断偏差在哪
        let weightChange = weightChange(in: fusedDays)
        let projectedChange = projectedChange(
            in: fusedDays, formulaTDEE: formulaTDEE,
            addBurned: profile?.addBurnedToBudget ?? false, calendar: calendar
        )

        var measured: Double?
        var measuredNote: String?
        switch adaptive {
        case .available(let kcal, _):
            measured = kcal
        case .unreliable(let kcal, _):
            measured = nil
            measuredNote = String(localized: "反推得到 \(Int(kcal)) kcal,但偏离公式估算过远,多半是记录不全,不可信")
        case .insufficientData(let reason):
            measured = nil
            measuredNote = reason
        }

        let avgProtein = logged.isEmpty ? 0 : exportedDays.reduce(0.0) { $0 + $1.totals.proteinG } / Double(max(exportedDays.count, 1))

        return Payload(
            schemaVersion: schemaVersion,
            exportedAt: ISO8601DateFormatter().string(from: .now),
            timezone: TimeZone.current.identifier,
            range: .init(
                from: dayFormatter.string(from: fusedDays.first?.date ?? .now),
                to: dayFormatter.string(from: fusedDays.last?.date ?? .now),
                daysWithData: withData.count
            ),
            profile: .init(
                sex: profile?.sex.rawValue ?? "male",
                age: profile?.age,
                heightCm: profile?.heightCm ?? 0,
                currentWeightKg: entries.filter { $0.metric == .weight }.max(by: { $0.date < $1.date })?.value,
                goalWeightKg: profile?.goalWeight ?? 0,
                weeklyRateKg: profile?.weeklyRateKg ?? 0,
                activityLevel: profile?.activityLevel.rawValue ?? "sedentary",
                estimatedTdee: formulaTDEE,
                measuredTdee: measured,
                measuredTdeeNote: measuredNote
            ),
            settings: .init(
                burnedCaloriesAddedToBudget: profile?.addBurnedToBudget ?? false,
                usingMeasuredTdee: profile?.useAdaptiveTDEE ?? false
            ),
            summary: .init(
                avgKcal: logged.isEmpty ? 0 : Int((logged.reduce(0) { $0 + $1.intakeKcal } / Double(logged.count)).rounded()),
                avgProteinG: NutritionCalculator.round1(avgProtein),
                kcalWithin10PctOfTargetDays: logged.filter(\.isOnTarget).count,
                checkInStreak: FusedSeriesBuilder.streak(entries: entries, dayLogs: dayLogs, calendar: calendar),
                weightChangeKg: weightChange,
                projectedWeightChangeKg: projectedChange
            ),
            days: exportedDays,
            analysisPrompt: prompt
        )
    }

    /// 窗口内首末体重之差
    private static func weightChange(in days: [FusedDay]) -> Double? {
        let weighed = days.compactMap { $0.weight }
        guard let first = weighed.first, let last = weighed.last, weighed.count > 1 else { return nil }
        return NutritionCalculator.round1(last - first)
    }

    /// 按摄入推出的体重变化
    private static func projectedChange(
        in days: [FusedDay],
        formulaTDEE: Double,
        addBurned: Bool,
        calendar: Calendar
    ) -> Double? {
        guard formulaTDEE > 0, let start = days.first(where: { $0.weight != nil })?.weight else { return nil }
        let points = EnergyBalanceService.projectedWeights(
            startWeightKg: start,
            intakes: FusedSeriesBuilder.dailyIntakes(from: Array(days.drop { $0.weight == nil })),
            tdeeFor: { _ in formulaTDEE },
            addBurnedToBudget: addBurned,
            calendar: calendar
        )
        guard let last = points.last else { return nil }
        return NutritionCalculator.round1(last.kg - start)
    }

    /// 编码成便于阅读的 JSON
    static func encode(_ payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
