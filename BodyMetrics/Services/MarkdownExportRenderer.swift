import Foundation

/// 把导出包渲染成 Markdown。
///
/// 这份数据是**粘进聊天框给模型看的**,不被任何程序解析(备份/导入走
/// BackupService 那条独立通道),所以默认用 Markdown 而不是 JSON:
/// 同样的内容 token 少得多、模型在分析任务上对表格与散文的推理更顺,
/// 而且用户自己粘出去之前能一眼扫过去确认数据对不对。
///
/// 与 JSON 共用同一个 `AIExportBuilder.Payload`,两种格式的内容不会走偏。
enum MarkdownExportRenderer {

    static func render(_ payload: AIExportBuilder.Payload) -> String {
        var lines: [String] = []

        lines.append("# " + String(localized: "饮食、训练与体重记录"))
        lines.append("")
        lines.append(contentsOf: profileSection(payload))
        lines.append(contentsOf: summarySection(payload))
        lines.append(contentsOf: dailyTable(payload))
        lines.append(contentsOf: dailyDetails(payload))
        lines.append("## " + String(localized: "分析请求"))
        lines.append("")
        lines.append(payload.analysisPrompt)
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - 基本信息

    private static func profileSection(_ payload: AIExportBuilder.Payload) -> [String] {
        let p = payload.profile
        var lines = ["## " + String(localized: "基本信息"), ""]

        let sex = Sex(rawValue: p.sex)?.label ?? p.sex
        let activity = ActivityLevel(rawValue: p.activityLevel)?.label ?? p.activityLevel
        lines.append("- " + String(localized: "性别") + "：\(sex)"
                     + (p.age.map { "　" + String(localized: "年龄") + "：\($0)" } ?? "")
                     + "　" + String(localized: "身高") + "：\(StatsCalculator.format1(p.heightCm)) cm")

        if let current = p.currentWeightKg {
            lines.append("- " + String(localized: "当前体重")
                         + "：\(StatsCalculator.format1(current)) kg　"
                         + String(localized: "目标体重") + "：\(StatsCalculator.format1(p.goalWeightKg)) kg"
                         + "（\(rateText(p.weeklyRateKg))）")
        }
        lines.append("- " + String(localized: "活动强度") + "：\(activity)")
        lines.append("- " + String(localized: "公式估算 TDEE") + "：\(Int(p.estimatedTdee)) kcal")

        // 实测代谢:有就给数字,没有就说清为什么没有,不留一个空字段让模型自己猜
        if let measured = p.measuredTdee {
            let delta = p.estimatedTdee > 0
                ? Int(((measured - p.estimatedTdee) / p.estimatedTdee * 100).rounded())
                : 0
            let deltaText = delta == 0 ? "" : "（\(delta > 0 ? "+" : "")\(delta)%）"
            lines.append("- " + String(localized: "实测代谢（由体重变化反推）") + "：\(Int(measured)) kcal\(deltaText)")
        } else {
            lines.append("- " + String(localized: "实测代谢") + "："
                         + String(localized: "不可用") + "（\(p.measuredTdeeNote ?? "")）")
        }

        lines.append("- " + String(localized: "训练消耗回补额度")
                     + "：" + (payload.settings.burnedCaloriesAddedToBudget
                              ? String(localized: "是") : String(localized: "否")))
        lines.append("")
        return lines
    }

    private static func rateText(_ rate: Double) -> String {
        guard rate != 0 else { return String(localized: "维持体重") }
        let sign = rate < 0 ? "−" : "+"
        return String(localized: "每周") + " \(sign)\(StatsCalculator.format1(abs(rate))) kg"
    }

    // MARK: - 区间概览

    private static func summarySection(_ payload: AIExportBuilder.Payload) -> [String] {
        let s = payload.summary
        var lines = ["## " + String(localized: "区间概览"), ""]
        lines.append("- " + String(localized: "范围")
                     + "：\(payload.range.from) ~ \(payload.range.to)"
                     + "（" + String(localized: "有数据") + " \(payload.range.daysWithData) "
                     + String(localized: "天") + "）")
        lines.append("- " + String(localized: "平均热量") + "：\(s.avgKcal) kcal　"
                     + String(localized: "平均蛋白质") + "：\(StatsCalculator.format1(s.avgProteinG)) g")
        lines.append("- " + String(localized: "热量达标天（目标 ±10% 内）") + "：\(s.kcalWithin10PctOfTargetDays)")
        lines.append("- " + String(localized: "连续打卡") + "：\(s.checkInStreak) " + String(localized: "天"))

        // 实测变化与预测变化并排给,模型才能判断偏差出在哪
        if let actual = s.weightChangeKg {
            var line = "- " + String(localized: "体重实际变化") + "：\(signed(actual)) kg"
            if let projected = s.projectedWeightChangeKg {
                line += "　" + String(localized: "按摄入预测") + "：\(signed(projected)) kg"
            }
            lines.append(line)
        }
        lines.append("")
        return lines
    }

    private static func signed(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + StatsCalculator.format1(abs(value))
    }

    // MARK: - 每日汇总表

    private static func dailyTable(_ payload: AIExportBuilder.Payload) -> [String] {
        guard !payload.days.isEmpty else {
            return ["## " + String(localized: "每日汇总"), "",
                    String(localized: "这个范围里没有记录。"), ""]
        }
        var lines = ["## " + String(localized: "每日汇总"), ""]
        lines.append("| " + [
            String(localized: "日期"), String(localized: "体重"), String(localized: "热量"),
            String(localized: "目标"), String(localized: "蛋白质"), String(localized: "脂肪"),
            String(localized: "碳水"), String(localized: "训练消耗"), String(localized: "训练容量"),
        ].joined(separator: " | ") + " |")
        lines.append("|" + String(repeating: "---|", count: 9))

        for day in payload.days {
            lines.append("| " + [
                day.date,
                day.weightKg.map { StatsCalculator.format1($0) } ?? "—",
                String(day.totals.kcal),
                day.target.map { String(Int($0.kcal)) } ?? "—",
                StatsCalculator.format1(day.totals.proteinG),
                StatsCalculator.format1(day.totals.fatG),
                StatsCalculator.format1(day.totals.carbG),
                day.totals.kcalBurned > 0 ? String(day.totals.kcalBurned) : "—",
                day.totals.trainingVolumeKg > 0 ? String(day.totals.trainingVolumeKg) : "—",
            ].joined(separator: " | ") + " |")
        }
        lines.append("")
        return lines
    }

    // MARK: - 每日明细

    private static func dailyDetails(_ payload: AIExportBuilder.Payload) -> [String] {
        let withDetail = payload.days.filter {
            !$0.meals.isEmpty || !$0.strength.isEmpty || !$0.cardio.isEmpty
                || !$0.note.isEmpty
        }
        guard !withDetail.isEmpty else { return [] }

        var lines = ["## " + String(localized: "每日明细"), ""]
        for day in withDetail {
            lines.append("### \(day.date)")
            var head = ""
            if let weight = day.weightKg {
                head += String(localized: "体重") + " \(StatsCalculator.format1(weight)) kg　"
            }
            head += String(localized: "摄入") + " \(day.totals.kcal)"
            if let target = day.target { head += " / \(Int(target.kcal))" }
            head += " kcal"
            lines.append(head)
            lines.append("")

            for meal in day.meals {
                let label = MealType(rawValue: meal.type)?.label ?? meal.type
                lines.append("**\(label)**")
                for item in meal.items {
                    let macros = MacroTotals(kcal: 0, proteinG: item.proteinG,
                                             fatG: item.fatG, carbG: item.carbG)
                    lines.append("- \(item.name) \(NumberText.text(item.amount)) \(item.unit)"
                                 + " — \(item.kcal) kcal，\(macros.summaryText)")
                }
                lines.append("")
            }

            if !day.strength.isEmpty {
                lines.append("**" + String(localized: "力量") + "**")
                for workout in day.strength {
                    var line = "- \(workout.exercise) — \(setsText(workout.sets))"
                    line += "，" + String(localized: "容量") + " \(workout.volumeKg) kg"
                    if workout.estimated1rmKg > 0 {
                        line += "，" + String(localized: "估算 1RM") + " \(workout.estimated1rmKg) kg"
                    }
                    if let burn = workout.kcalBurned {
                        line += "，" + String(localized: "消耗") + " \(Int(burn.value)) kcal\(sourceNote(burn.source))"
                    }
                    lines.append(line)
                }
                lines.append("")
            }

            if !day.cardio.isEmpty {
                lines.append("**" + String(localized: "有氧") + "**")
                for session in day.cardio {
                    var line = "- \(session.exercise) \(NumberText.text(session.durationMin)) "
                        + String(localized: "分钟")
                    if let distance = session.distanceKm, distance > 0 {
                        line += " \(NumberText.text(distance)) km"
                    }
                    line += "，" + String(localized: "消耗")
                        + " \(Int(session.kcalBurned.value)) kcal\(sourceNote(session.kcalBurned.source))"
                    lines.append(line)
                }
                lines.append("")
            }

            if !day.note.isEmpty {
                lines.append("> " + String(localized: "备注") + "：\(day.note)")
                lines.append("")
            }
        }
        return lines
    }

    /// 相同的组合并成 "3×5 × 100kg",逐组列出会把表撑得很长
    private static func setsText(_ sets: [AIExportBuilder.Payload.Day.Strength.Set]) -> String {
        let working = sets.filter { !$0.warmup }
        guard !working.isEmpty else { return String(localized: "仅热身组") }
        var parts: [String] = []
        var index = 0
        while index < working.count {
            let current = working[index]
            var count = 1
            while index + count < working.count,
                  working[index + count].reps == current.reps,
                  working[index + count].weightKg == current.weightKg {
                count += 1
            }
            let weight = current.weightKg > 0 ? " × \(NumberText.text(current.weightKg))kg" : ""
            parts.append(count > 1 ? "\(count) 组 × \(current.reps)\(weight)" : "\(current.reps)\(weight)")
            index += count
        }
        return parts.joined(separator: "，")
    }

    /// device 来源要标出来:误差可达 ±25%,不标注模型会当成精确值用
    private static func sourceNote(_ source: String) -> String {
        source == KcalSource.device.rawValue
            ? "（" + String(localized: "设备读数，误差可达 ±25%") + "）"
            : ""
    }
}
