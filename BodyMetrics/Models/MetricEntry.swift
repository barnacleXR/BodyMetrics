import Foundation
import SwiftData

/// 一条指标记录(追加式,允许同日同指标多条;当日代表值取最新一条)
@Model
final class MetricEntry {
    var id: UUID = UUID()
    var metric: Metric = Metric.weight
    var value: Double = 0
    var date: Date = Date.now

    init(metric: Metric, value: Double, date: Date) {
        self.metric = metric
        self.value = value
        self.date = date
    }
}
