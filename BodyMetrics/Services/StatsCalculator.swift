import Foundation

/// 统计计算服务(纯函数,输入记录数组与参数,输出展示数据;规则见 PRD §4)
enum StatsCalculator {

    // MARK: - 单日代表值

    /// 指定日该指标的最新一条记录值
    static func latestValue(on day: Date, metric: Metric, in entries: [MetricEntry], calendar: Calendar = .current) -> Double? {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return entries
            .filter { $0.metric == metric && $0.date >= dayStart && $0.date < dayEnd }
            .max(by: { $0.date < $1.date })?
            .value
    }

    // MARK: - 较昨日

    /// 较昨日变化:今日最新 − 昨日最新;任一缺失返回 nil
    static func changeVsYesterday(in entries: [MetricEntry], now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard
            let today = latestValue(on: now, metric: .weight, in: entries, calendar: calendar),
            let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now),
            let yesterday = latestValue(on: yesterdayDate, metric: .weight, in: entries, calendar: calendar)
        else { return nil }
        return today - yesterday
    }

    // MARK: - 本周状态

    /// 本周体重均值 − 上周体重均值(周一为一周开始)
    static func weeklyChange(in entries: [MetricEntry], now: Date = .now, calendar: Calendar = .current) -> Double? {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2 // 周一
        let weekday = weekCalendar.component(.weekday, from: now)
        let daysFromMonday = (weekday + 5) % 7
        guard let mondayDate = weekCalendar.date(byAdding: .day, value: -daysFromMonday, to: now) else { return nil }
        let thisMonday = weekCalendar.startOfDay(for: mondayDate)
        guard
            let lastMonday = weekCalendar.date(byAdding: .day, value: -7, to: thisMonday),
            let nextMonday = weekCalendar.date(byAdding: .day, value: 7, to: thisMonday)
        else { return nil }

        let weightEntries = entries.filter { $0.metric == .weight }
        let thisWeek = weightEntries.filter { $0.date >= thisMonday && $0.date < nextMonday }
        let lastWeek = weightEntries.filter { $0.date >= lastMonday && $0.date < thisMonday }
        guard let thisAvg = dailyMean(thisWeek, calendar: weekCalendar),
              let lastAvg = dailyMean(lastWeek, calendar: weekCalendar)
        else { return nil }
        return thisAvg - lastAvg
    }

    /// 窗口内按日分组,取每日最新一条后求均值(同日多条不重复加权)
    private static func dailyMean(_ entries: [MetricEntry], calendar: Calendar) -> Double? {
        let dailyLatest: [Double] = Dictionary(grouping: entries, by: { calendar.startOfDay(for: $0.date) })
            .values
            .compactMap { $0.max(by: { $0.date < $1.date })?.value }
        guard !dailyLatest.isEmpty else { return nil }
        return dailyLatest.reduce(0, +) / Double(dailyLatest.count)
    }

    /// 本周状态展示:文案 + 带符号变化文本
    static func weeklyState(in entries: [MetricEntry], now: Date = .now, calendar: Calendar = .current) -> (label: String, deltaText: String)? {
        guard let change = weeklyChange(in: entries, now: now, calendar: calendar) else { return nil }
        let label: String
        if abs(change) <= 0.3 {
            label = String(localized: "趋势平稳")
        } else {
            label = change < 0 ? String(localized: "下降") : String(localized: "上升")
        }
        return (label, signedText(change, unit: "kg"))
    }

    // MARK: - 目标进度

    /// (首个体重记录 − 当前体重) / (首个体重记录 − 目标体重),截断 0...1;数据不足或分母为 0 时为 0
    static func goalProgress(in entries: [MetricEntry], goal: Double, now: Date = .now, calendar: Calendar = .current) -> Double {
        let weightEntries = entries.filter { $0.metric == .weight }
        guard let first = weightEntries.min(by: { $0.date < $1.date }) else { return 0 }
        guard let current = latestValue(on: now, metric: .weight, in: entries, calendar: calendar) else { return 0 }
        let denominator = first.value - goal
        guard abs(denominator) > 0.0001 else { return 0 }
        return min(max((first.value - current) / denominator, 0), 1)
    }

    // MARK: - 与能量收支层的桥接

    /// 体重记录 → 纯值样本(供 EnergyBalanceService 使用,那一层不依赖 SwiftData)
    static func weightSamples(from entries: [MetricEntry]) -> [WeightSample] {
        entries
            .filter { $0.metric == .weight }
            .map { WeightSample(date: $0.date, kg: $0.value) }
    }

    /// 截至某日往前 n 天的体重移动平均(按日取最新一条)。
    /// 单日体重的水分波动可达 ±1 kg,凡是要"比较两个时间点的体重"的地方都必须走这里
    static func trailingAverage(
        days: Int,
        endingOn day: Date,
        in entries: [MetricEntry],
        calendar: Calendar = .current
    ) -> Double? {
        let end = calendar.startOfDay(for: day)
        guard days > 0, let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return nil }
        let window = weightSamples(from: entries).filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= start && d <= end
        }
        return EnergyBalanceService.dailyLatestMean(window, calendar: calendar)
    }

    // MARK: - BMI

    /// BMI = 体重(kg) ÷ (身高 m)²
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let heightM = heightCm / 100
        guard heightM > 0 else { return 0 }
        return weightKg / (heightM * heightM)
    }

    // MARK: - 趋势洞察(近 30 天窗口)

    /// 窗口首条 vs 最后一条;|Δ| ≤ 0.5 平稳,否则向下/向上
    static func trendInsight(in entries: [MetricEntry], now: Date = .now, calendar: Calendar = .current) -> (title: String, detail: String)? {
        let weightEntries = entries.filter { $0.metric == .weight }
        guard let windowStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) else { return nil }
        let window = weightEntries.filter { $0.date >= windowStart && $0.date <= now }
        guard let first = window.min(by: { $0.date < $1.date }),
              let last = window.max(by: { $0.date < $1.date }),
              first.id != last.id
        else { return nil }

        let delta = last.value - first.value
        let title: String
        let detail: String
        if abs(delta) <= 0.5 {
            title = String(localized: "保持平稳")
            detail = String(localized: "近 30 天变化 %@").replacingOccurrences(of: "%@", with: format1(abs(delta)) + " kg")
        } else if delta < 0 {
            title = String(localized: "稳定向下")
            detail = String(localized: "近 30 天已减少 %@").replacingOccurrences(of: "%@", with: format1(abs(delta)) + " kg")
        } else {
            title = String(localized: "稳定上升")
            detail = String(localized: "近 30 天已增加 %@").replacingOccurrences(of: "%@", with: format1(abs(delta)) + " kg")
        }
        return (title, detail)
    }

    // MARK: - 格式化

    /// 保留 1 位小数(固定 en_US_POSIX,避免德语等 locale 输出逗号导致 CSV 裂列)
    static func format1(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// 带符号文本,如 "−0.6 kg"(负号用减号;正数带 +)
    static func signedText(_ value: Double, unit: String) -> String {
        let sign = value < 0 ? "−" : "+"
        return sign + format1(abs(value)) + " " + unit
    }
}
