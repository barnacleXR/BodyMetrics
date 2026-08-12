import Foundation
import SwiftData

/// 一次有氧训练
@Model
final class CardioSession {
    var name: String = ""
    var durationMin: Double = 0
    /// 距离可选:力量型有氧(如划船机)未必记距离
    var distanceKm: Double? = nil
    var kcalBurned: Double = 0
    var kcalSource: KcalSource = KcalSource.manual
    var sortIndex: Int = 0

    var dayLog: DayLog?

    init(
        name: String,
        durationMin: Double,
        distanceKm: Double? = nil,
        kcalBurned: Double = 0,
        kcalSource: KcalSource = .manual,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.durationMin = durationMin
        self.distanceKm = distanceKm
        self.kcalBurned = kcalBurned
        self.kcalSource = kcalSource
        self.sortIndex = sortIndex
    }
}
