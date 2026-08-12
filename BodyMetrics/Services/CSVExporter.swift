import Foundation

/// CSV 导出(UTF-8 with BOM,Excel/Numbers 中文不乱码)。
///
/// 一份文件同时含体重与每日饮食训练:两个领域已经合成一个产品,
/// 导出成两份互不相干的表就等于把融合又拆回去了。
enum CSVExporter {
    static let weightHeader = String(localized: "日期,时间,指标,数值")
    static let dailyHeader = String(localized: "日期,体重kg,热量kcal,目标kcal,蛋白g,脂肪g,碳水g,训练消耗kcal,训练容量kg,备注")

    /// 体重明细 + 每日汇总,写在同一个文件的两段里
    static func exportCombinedCSV(
        entries: [MetricEntry],
        dayLogs: [DayLog],
        targets: [NutritionTarget],
        fileName: String = String(localized: "体重与饮食记录.csv"),
        calendar: Calendar = .current
    ) -> URL? {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")

        var csv = "\u{FEFF}"

        // 第一段:每日汇总(把两个领域并到一行上)
        csv += String(localized: "# 每日汇总") + "\n" + dailyHeader + "\n"
        let allDays = Set(
            dayLogs.map { calendar.startOfDay(for: $0.dayStart) }
                + entries.map { calendar.startOfDay(for: $0.date) }
        ).sorted()
        for day in allDays {
            let log = dayLogs.first { calendar.isDate($0.dayStart, inSameDayAs: day) }
            let totals = log.map { NutritionCalculator.totals(for: $0) } ?? .zero
            let weight = StatsCalculator.latestValue(on: day, metric: .weight, in: entries, calendar: calendar)
            let target = NutritionCalculator.target(on: day, in: targets, calendar: calendar)?.kcal ?? 0
            let note = (log?.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += [
                dayFormatter.string(from: day),
                weight.map { StatsCalculator.format1($0) } ?? "",
                String(Int(totals.macros.kcal.rounded())),
                target > 0 ? String(Int(target)) : "",
                StatsCalculator.format1(totals.macros.proteinG),
                StatsCalculator.format1(totals.macros.fatG),
                StatsCalculator.format1(totals.macros.carbG),
                String(Int(totals.burnedKcal.rounded())),
                String(Int(totals.volumeKg)),
                note.isEmpty ? "" : "\"\(note)\"",
            ].joined(separator: ",") + "\n"
        }

        // 第二段:体重明细(同日多条都在)
        csv += "\n" + String(localized: "# 体重明细") + "\n" + weightHeader + "\n"
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            csv += [
                dayFormatter.string(from: entry.date),
                timeFormatter.string(from: entry.date),
                entry.metric.label,
                StatsCalculator.format1(entry.value),
            ].joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
