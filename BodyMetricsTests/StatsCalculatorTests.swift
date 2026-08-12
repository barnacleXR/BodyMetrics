import Testing
import Foundation
@testable import BodyMetrics

struct StatsCalculatorTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private func day(_ offset: Int, hour: Int = 8) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: today)!)!
    }

    @Test func trailingAverageUsesDailyLatestAndIgnoresOutsideWindow() {
        let entries = [
            MetricEntry(metric: .weight, value: 70.0, date: day(-1)),
            // 同一天两条:只取当天最新那条,否则称两次的日子会被加倍加权
            MetricEntry(metric: .weight, value: 71.0, date: day(0, hour: 8)),
            MetricEntry(metric: .weight, value: 72.0, date: day(0, hour: 20)),
            // 窗口之外
            MetricEntry(metric: .weight, value: 100.0, date: day(-10)),
            // 别的指标不该混进来
            MetricEntry(metric: .bodyFat, value: 18.0, date: day(0)),
        ]
        let average = StatsCalculator.trailingAverage(days: 7, endingOn: .now, in: entries)
        #expect(average != nil)
        #expect(abs(average! - 71.0) < 0.0001)   // (70 + 72) / 2
    }

    @Test func trailingAverageIsNilWithoutData() {
        #expect(StatsCalculator.trailingAverage(days: 7, endingOn: .now, in: []) == nil)
    }

    @Test func weightSamplesFilterOutOtherMetrics() {
        let entries = [
            MetricEntry(metric: .weight, value: 70, date: day(0)),
            MetricEntry(metric: .bodyFat, value: 18, date: day(0)),
        ]
        #expect(StatsCalculator.weightSamples(from: entries).count == 1)
    }
}
