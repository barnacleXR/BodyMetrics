import SwiftUI
import SwiftData
import Charts

/// 趋势页:指标/范围分段 + 折线图 + 趋势洞察
struct TrendView: View {
    enum TrendMetric: String, CaseIterable, Hashable {
        case weight, bodyFat, bmi

        var label: String {
            switch self {
            case .weight: return String(localized: "体重")
            case .bodyFat: return String(localized: "体脂率")
            case .bmi: return "BMI"
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

    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var profiles: [UserProfile]

    @State private var metric: TrendMetric = .weight
    @State private var range: TrendRange = .month

    private var profile: UserProfile? { profiles.first }

    // MARK: - 数据

    /// 窗口内每日一点(取当日最新一条)
    private var points: [TrendPoint] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: calendar.startOfDay(for: .now)) else { return [] }
        var result: [TrendPoint] = []
        var day = start
        let today = calendar.startOfDay(for: .now)
        while day <= today {
            if let value = value(on: day, calendar: calendar) {
                result.append(TrendPoint(date: day, value: value))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private func value(on day: Date, calendar: Calendar) -> Double? {
        switch metric {
        case .weight:
            return StatsCalculator.latestValue(on: day, metric: .weight, in: entries, calendar: calendar)
        case .bodyFat:
            return StatsCalculator.latestValue(on: day, metric: .bodyFat, in: entries, calendar: calendar)
        case .bmi:
            guard let weight = StatsCalculator.latestValue(on: day, metric: .weight, in: entries, calendar: calendar),
                  let profile
            else { return nil }
            return StatsCalculator.bmi(weightKg: weight, heightCm: profile.heightCm)
        }
    }

    private var latestText: String {
        points.last.map { StatsCalculator.format1($0.value) } ?? "—"
    }

    private var unitText: String {
        metric == .bodyFat ? String(localized: "%") : (metric == .bmi ? "" : String(localized: "kg"))
    }

    /// 窗口内末点 − 首点(带符号文本)
    private var trendText: String? {
        guard let first = points.first, let last = points.last, first.id != last.id else { return nil }
        return StatsCalculator.signedText(last.value - first.value, unit: "kg")
    }

    private var trendIsDown: Bool {
        guard let first = points.first, let last = points.last, first.id != last.id else { return false }
        return last.value - first.value < 0
    }

    /// 纵轴范围:按窗口内数据动态取,上下各留 15% 余量。
    /// 不从 0 起——体重这类数值区间窄,从 0 起会把折线压成一条直线,看不出变化
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        guard high > low else {
            // 全窗口只有一个值(或全都相同):给一个固定薄区间,避免上下界相等
            let pad = Swift.max(abs(low) * 0.02, 0.5)
            return (low - pad)...(high + pad)
        }
        let pad = (high - low) * 0.15
        return (low - pad)...(high + pad)
    }

    /// 横轴 3 个标签:起点 / 中点 / 今天
    private var axisDates: [Date] {
        guard let start = points.first?.date, let end = points.last?.date else { return [] }
        let mid = start.addingTimeInterval((end.timeIntervalSince(start)) / 2)
        return [start, mid, end]
    }

    private var insight: (title: String, detail: String)? {
        StatsCalculator.trendInsight(in: entries)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text("趋势")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)

                    Picker("", selection: $metric) {
                        ForEach(TrendMetric.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("", selection: $range) {
                        ForEach(TrendRange.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 10)

                    chartPanel
                        .padding(.top, 16)

                    if let insight {
                        insightCard(insight)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - 图表面板

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(latestText)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color("TextPrimary"))
                if !unitText.isEmpty {
                    Text(unitText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer()
                if let trendText {
                    Text("\(trendIsDown ? "↓" : "↑") \(trendText.replacingOccurrences(of: "+", with: ""))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(trendIsDown ? Color("BrandGreen") : Color.red.opacity(0.8))
                }
            }
            .padding(.top, 4)

            if points.isEmpty {
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
                Chart(points) { point in
                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("值", point.value)
                    )
                    .foregroundStyle(Color("BrandGreen"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color("TextSecondary").opacity(0.3))
                        AxisValueLabel(format: .dateTime.month().day())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color("TextSecondary").opacity(0.3))
                        AxisValueLabel()
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
                .frame(height: 200)
                .padding(.top, 14)
            }
        }
        .padding(16)
        .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - 趋势洞察

    private func insightCard(_ insight: (title: String, detail: String)) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color("TextSecondary"))
                .frame(width: 32, height: 32)
                .background(Color("PageBackground"), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 14))
                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 17))
    }
}

#Preview {
    TrendView()
        .modelContainer(for: [MetricEntry.self, UserProfile.self], inMemory: true)
}
