import SwiftUI
import SwiftData
import Charts

/// 趋势页:体重 / 热量 / 训练容量共用一条时间轴,再加上把两边接起来的两张卡——
/// 体重预测线(由摄入推出体重该怎么走)与实测代谢(由体重反推真实 TDEE)
struct TrendView: View {
    enum TrendMetric: String, CaseIterable, Hashable {
        case weight, kcal, volume, bodyFat

        var label: String {
            switch self {
            case .weight: return String(localized: "体重")
            case .kcal: return String(localized: "热量")
            case .volume: return String(localized: "容量")
            case .bodyFat: return String(localized: "体脂率")
            }
        }
    }

    enum TrendRange: String, CaseIterable, Hashable {
        case week, month, threeMonths

        var label: String {
            switch self {
            case .week: return String(localized: "1周")
            case .month: return String(localized: "1个月")
            case .threeMonths: return String(localized: "3个月")
            }
        }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            }
        }
    }

    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var dayLogs: [DayLog]
    @Query private var profiles: [UserProfile]
    @Query(sort: \NutritionTarget.effectiveFrom) private var targets: [NutritionTarget]
    @Environment(\.modelContext) private var context

    @State private var metric: TrendMetric = .weight
    @State private var range: TrendRange = .month
    @State private var showProjection = true
    @State private var toastMessage: ToastMessage?

    private let calendar = Calendar.current
    private var profile: UserProfile? { profiles.first }

    // MARK: - 数据

    private var days: [FusedDay] {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) else { return [] }
        return FusedSeriesBuilder.build(
            from: start, to: today,
            entries: entries, dayLogs: dayLogs, targets: targets, calendar: calendar
        )
    }

    /// 分析窗口固定 28 天,不跟着显示区间走——自适应代谢的准入门槛是按 28 天定的
    private var analysisDays: [FusedDay] {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -27, to: today) else { return [] }
        return FusedSeriesBuilder.build(
            from: start, to: today,
            entries: entries, dayLogs: dayLogs, targets: targets, calendar: calendar
        )
    }

    private var latestWeight: Double? {
        entries.filter { $0.metric == .weight }.max(by: { $0.date < $1.date })?.value
    }

    private var formulaTDEE: Double {
        guard let profile, let age = profile.age, let weight = latestWeight else { return 0 }
        return NutritionCalculator.tdee(
            sex: profile.sex, weightKg: weight, heightCm: profile.heightCm,
            age: age, activityLevel: profile.activityLevel
        )
    }

    private var adaptiveResult: EnergyBalanceService.AdaptiveTDEE {
        EnergyBalanceService.adaptiveTDEE(
            weights: StatsCalculator.weightSamples(from: entries),
            intakes: FusedSeriesBuilder.dailyIntakes(from: analysisDays),
            formulaTDEE: formulaTDEE,
            calendar: calendar
        )
    }

    /// 由摄入推出的体重曲线。起点用窗口内第一个实测体重
    private var projectedPoints: [EnergyBalanceService.ProjectedPoint] {
        guard metric == .weight, showProjection, formulaTDEE > 0,
              let firstWeight = days.first(where: { $0.weight != nil })?.weight
        else { return [] }
        let fromFirstWeighIn = Array(days.drop { $0.weight == nil })
        return EnergyBalanceService.projectedWeights(
            startWeightKg: firstWeight,
            intakes: FusedSeriesBuilder.dailyIntakes(from: fromFirstWeighIn),
            tdeeFor: { _ in formulaTDEE },
            addBurnedToBudget: profile?.addBurnedToBudget ?? false,
            calendar: calendar
        )
    }

    private var measuredPoints: [(date: Date, value: Double)] {
        days.compactMap { day in
            switch metric {
            case .weight:
                return day.weight.map { (day.date, $0) }
            case .bodyFat:
                return StatsCalculator.latestValue(on: day.date, metric: .bodyFat, in: entries, calendar: calendar)
                    .map { (day.date, $0) }
            case .kcal:
                return day.hasIntakeRecord ? (day.date, day.intakeKcal) : nil
            case .volume:
                return day.volumeKg > 0 ? (day.date, day.volumeKg) : nil
            }
        }
    }

    private var unitText: String {
        switch metric {
        case .weight, .volume: return "kg"
        case .bodyFat: return "%"
        case .kcal: return "kcal"
        }
    }

    private var latestText: String {
        guard let last = measuredPoints.last?.value else { return "—" }
        return (metric == .kcal || metric == .volume)
            ? String(Int(last.rounded()))
            : StatsCalculator.format1(last)
    }

    private var yDomain: ClosedRange<Double> {
        var values = measuredPoints.map(\.value)
        if metric == .weight { values += projectedPoints.map(\.kg) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        // 热量与容量从 0 起看得出绝对量;体重区间窄,从 0 起会压成一条直线
        if metric == .kcal || metric == .volume {
            return 0...(Swift.max(high * 1.15, 1))
        }
        guard high > low else {
            let pad = Swift.max(abs(low) * 0.02, 0.5)
            return (low - pad)...(high + pad)
        }
        let pad = (high - low) * 0.15
        return (low - pad)...(high + pad)
    }

    private struct RangeStats {
        var avgKcal = 0
        var avgProtein = 0.0
        var onTargetDays = 0
        var loggedDays = 0
        var volume = 0
    }

    private var stats: RangeStats {
        let window = days
        let logged = window.filter(\.hasIntakeRecord)
        var result = RangeStats()
        result.loggedDays = logged.count
        result.onTargetDays = logged.filter(\.isOnTarget).count
        result.volume = Int(window.reduce(0) { $0 + $1.volumeKg })
        if !logged.isEmpty {
            result.avgKcal = Int((logged.reduce(0) { $0 + $1.intakeKcal } / Double(logged.count)).rounded())
        }
        let proteinPerDay = dayLogs
            .filter { log in window.contains { calendar.isDate($0.date, inSameDayAs: log.dayStart) } }
            .map { NutritionCalculator.totals(for: $0).macros.proteinG }
        if !proteinPerDay.isEmpty {
            result.avgProtein = NutritionCalculator.round1(proteinPerDay.reduce(0, +) / Double(proteinPerDay.count))
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Picker("", selection: $metric) {
                        ForEach(TrendMetric.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("", selection: $range) {
                        ForEach(TrendRange.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 10)

                    chartPanel.padding(.top, 16)
                    statsGrid.padding(.top, 18)
                    AdaptiveTDEECard(
                        result: adaptiveResult,
                        isAdopted: profile?.useAdaptiveTDEE ?? false,
                        onAdopt: adoptAdaptive,
                        onRevert: revertAdaptive
                    )
                    .padding(.top, 18)
                    if let insight = StatsCalculator.trendInsight(in: entries) {
                        insightCard(insight).padding(.top, 18)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .toast($toastMessage)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("连续打卡 \(FusedSeriesBuilder.streak(entries: entries, dayLogs: dayLogs, calendar: calendar)) 天")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
                Text("趋势")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - 图表

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
                if metric == .weight && !projectedPoints.isEmpty {
                    Button {
                        showProjection.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showProjection ? "checkmark.square" : "square")
                                .font(.system(size: 10))
                            Text("按摄入预测")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color("BrandGreen"))
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(latestText)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color("TextPrimary"))
                Text(unitText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
            }
            .padding(.top, 4)

            if measuredPoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 26))
                        .foregroundStyle(Color("TextSecondary"))
                    Text("暂无数据")
                        .font(.system(size: 13))
                        .foregroundStyle(Color("TextSecondary"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                chart.frame(height: 200).padding(.top, 14)
                if metric == .weight && showProjection && !projectedPoints.isEmpty {
                    legend.padding(.top, 8)
                }
            }
        }
        .padding(16)
        .cardBackground(cornerRadius: 18)
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            if metric == .kcal || metric == .volume {
                ForEach(measuredPoints, id: \.date) { point in
                    BarMark(
                        x: .value(String(localized: "日期"), point.date, unit: .day),
                        y: .value(metric.label, point.value)
                    )
                    .foregroundStyle(barColor(for: point.date))
                }
                if metric == .kcal, let target = days.last?.targetKcal, target > 0 {
                    RuleMark(y: .value(String(localized: "目标"), target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color("TextSecondary"))
                }
            } else {
                // series 必须显式区分:不然实测与预测在同一天的两个点会被 Charts
                // 当成同一条线连起来,只有一天数据时直接画成一根竖线
                ForEach(measuredPoints, id: \.date) { point in
                    LineMark(
                        x: .value(String(localized: "日期"), point.date, unit: .day),
                        y: .value(metric.label, point.value),
                        series: .value(String(localized: "系列"), "measured")
                    )
                    .foregroundStyle(Color("BrandGreen"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    // 单点时线画不出来,补个点否则图是空的
                    PointMark(
                        x: .value(String(localized: "日期"), point.date, unit: .day),
                        y: .value(metric.label, point.value)
                    )
                    .foregroundStyle(Color("BrandGreen"))
                    .symbolSize(measuredPoints.count == 1 ? 40 : 0)
                }
                // 预测线:按摄入推出体重该怎么走。它和实测线的偏差本身就是信息
                ForEach(projectedPoints, id: \.day) { point in
                    LineMark(
                        x: .value(String(localized: "日期"), point.day, unit: .day),
                        y: .value(metric.label, point.kg),
                        series: .value(String(localized: "系列"), "projected")
                    )
                    .foregroundStyle(Color("TextSecondary"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color("TextSecondary").opacity(0.3))
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color("TextSecondary").opacity(0.3))
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
    }

    /// 热量图里达标日实心,偏离日淡一档
    private func barColor(for date: Date) -> Color {
        guard metric == .kcal,
              let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
        else { return Color("BrandGreen") }
        return day.isOnTarget ? Color("BrandGreen") : Color("BrandGreen").opacity(0.35)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Rectangle().fill(Color("BrandGreen")).frame(width: 14, height: 2)
                Text("实测").font(.system(size: 10)).foregroundStyle(Color("TextSecondary"))
            }
            HStack(spacing: 5) {
                Rectangle().fill(Color("TextSecondary")).frame(width: 14, height: 1)
                Text("按摄入预测").font(.system(size: 10)).foregroundStyle(Color("TextSecondary"))
            }
            Spacer()
        }
    }

    // MARK: - 统计卡

    private var statsGrid: some View {
        let s = stats
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            statTile(label: String(localized: "平均热量"), value: "\(s.avgKcal)")
            statTile(label: String(localized: "平均蛋白 g"), value: StatsCalculator.format1(s.avgProtein))
            statTile(label: String(localized: "热量达标天"), value: "\(s.onTargetDays)", suffix: " / \(s.loggedDays)")
            statTile(label: String(localized: "训练总容量 kg"), value: "\(s.volume)")
        }
    }

    private func statTile(label: String, value: String, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color("TextSecondary"))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundStyle(Color("TextPrimary"))
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .cardBackground()
    }

    private func insightCard(_ insight: (title: String, detail: String)) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color("TextSecondary"))
                .frame(width: 32, height: 32)
                .background(Color("PageBackground"), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.system(size: 14))
                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .cardBackground()
    }

    // MARK: - 采纳实测代谢

    /// 用实测代谢替代公式值重算目标。只在用户显式点击时发生
    private func adoptAdaptive() {
        guard case .available(let kcal, _) = adaptiveResult,
              let profile, let weight = latestWeight
        else { return }

        profile.useAdaptiveTDEE = true
        try? context.save()

        let dailyDelta = profile.weeklyRateKg * EnergyBalanceService.kcalPerKg / 7
        let bmr = NutritionCalculator.bmr(
            sex: profile.sex, weightKg: weight, heightCm: profile.heightCm, age: profile.age ?? 0
        )
        // 同样受基础代谢下限约束,换个代谢来源不等于可以无限压
        let target = Swift.max(kcal + dailyDelta, bmr)
        TargetPlanService.saveTarget(
            NutritionCalculator.macros(forKcal: target, weightKg: weight),
            in: context
        )
        toastMessage = ToastMessage(text: String(localized: "已按实测代谢重算目标"))
    }

    private func revertAdaptive() {
        guard let profile else { return }
        profile.useAdaptiveTDEE = false
        try? context.save()
        if let plan = TargetPlanService.currentPlan(profile: profile, entries: entries) {
            TargetPlanService.saveTarget(plan.macros, in: context)
        }
        toastMessage = ToastMessage(text: String(localized: "已改回公式估算值"))
    }
}

#Preview {
    TrendView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
