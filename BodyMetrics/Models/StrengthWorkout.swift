import Foundation
import SwiftData

/// 一个力量动作及其组数。
///
/// 动作名以字符串存储(而非引用动作库),所以动作库改名时必须同步改写历史记录,
/// 否则统计里同一个动作会裂成两条。见 `ExerciseLibraryService.rename`。
@Model
final class StrengthWorkout {
    var name: String = ""
    var kcalBurned: Double = 0
    var kcalSource: KcalSource = KcalSource.manual
    /// 同日内的排列顺序
    var sortIndex: Int = 0

    var dayLog: DayLog?

    @Relationship(deleteRule: .cascade, inverse: \StrengthSet.workout)
    var sets: [StrengthSet] = []

    init(name: String, kcalBurned: Double = 0, kcalSource: KcalSource = .manual, sortIndex: Int = 0) {
        self.name = name
        self.kcalBurned = kcalBurned
        self.kcalSource = kcalSource
        self.sortIndex = sortIndex
    }

    var orderedSets: [StrengthSet] {
        sets.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// 训练容量 = Σ(次数 × 重量),热身组不计
    var volumeKg: Double {
        orderedSets.filter { !$0.isWarmup }.reduce(0) { $0 + Double($1.reps) * $1.weightKg }
    }

    /// 本动作最好的一组的 e1RM
    var bestE1RM: Double {
        orderedSets
            .filter { !$0.isWarmup }
            .map { NutritionCalculator.e1rm(weightKg: $0.weightKg, reps: $0.reps) }
            .max() ?? 0
    }
}

/// 一组(次数 × 重量);热身组不计入容量与 e1RM
@Model
final class StrengthSet {
    var reps: Int = 0
    var weightKg: Double = 0
    var isWarmup: Bool = false
    var sortIndex: Int = 0

    var workout: StrengthWorkout?

    init(reps: Int, weightKg: Double, isWarmup: Bool = false, sortIndex: Int = 0) {
        self.reps = reps
        self.weightKg = weightKg
        self.isWarmup = isWarmup
        self.sortIndex = sortIndex
    }
}
