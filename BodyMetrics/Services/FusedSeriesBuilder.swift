import Foundation

/// 一天在同一时间轴上的全部信息
struct FusedDay: Identifiable {
    var id: Date { date }
    let date: Date
    let weight: Double?
    let intakeKcal: Double
    let burnedKcal: Double
    let volumeKg: Double
    let targetKcal: Double
    let hasIntakeRecord: Bool
    let hasAnyRecord: Bool

    var isOnTarget: Bool {
        NutritionCalculator.isKcalOnTarget(intakeKcal, target: targetKcal)
    }
}

/// 把体重、饮食、训练拼成同一条时间轴。
///
/// 日历、趋势、导出都从这里取数,免得三处各写一套按日聚合的逻辑而彼此对不上。
enum FusedSeriesBuilder {

    static func build(
        from startDay: Date,
        to endDay: Date,
        entries: [MetricEntry],
        dayLogs: [DayLog],
        targets: [NutritionTarget],
        calendar: Calendar = .current
    ) -> [FusedDay] {
        let start = calendar.startOfDay(for: startDay)
        let end = calendar.startOfDay(for: endDay)
        guard start <= end else { return [] }

        // 先按日索引,避免对每一天都做一次全表扫描
        let logsByDay = Dictionary(
            dayLogs.map { (calendar.startOfDay(for: $0.dayStart), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [FusedDay] = []
        var cursor = start
        while cursor <= end {
            let log = logsByDay[cursor]
            let totals = log.map { NutritionCalculator.totals(for: $0) } ?? .zero
            let hasIntake = !(log?.meals.allSatisfy { $0.items.isEmpty } ?? true)
            let weight = StatsCalculator.latestValue(on: cursor, metric: .weight, in: entries, calendar: calendar)

            result.append(FusedDay(
                date: cursor,
                weight: weight,
                intakeKcal: totals.macros.kcal,
                burnedKcal: totals.burnedKcal,
                volumeKg: totals.volumeKg,
                targetKcal: NutritionCalculator.target(on: cursor, in: targets, calendar: calendar)?.kcal ?? 0,
                hasIntakeRecord: hasIntake,
                hasAnyRecord: !(log?.isEmpty ?? true) || weight != nil
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// 连续打卡天数。当天有**任意**记录就算(体重或饮食或训练),不分两套。
    /// 今天还没记时从昨天起算——允许当天还没开始记
    static func streak(
        entries: [MetricEntry],
        dayLogs: [DayLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let loggedDays = Set(dayLogs.filter { !$0.isEmpty }.map { calendar.startOfDay(for: $0.dayStart) })
        let weighedDays = Set(entries.map { calendar.startOfDay(for: $0.date) })
        let active = loggedDays.union(weighedDays)

        var cursor = calendar.startOfDay(for: now)
        if !active.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while active.contains(cursor), count < 3650 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// 转成能量收支层要的纯值类型
    static func dailyIntakes(from days: [FusedDay]) -> [DailyIntake] {
        days.map {
            DailyIntake(
                day: $0.date,
                intakeKcal: $0.intakeKcal,
                burnedKcal: $0.burnedKcal,
                hasIntakeRecord: $0.hasIntakeRecord
            )
        }
    }
}
