import Foundation
import SwiftData

/// 全部持久化类型。App 与各 Preview 共用一处,避免加了新模型却忘了在某个 Preview 里注册
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        MetricEntry.self, UserProfile.self, Reminder.self,
        DayLog.self, Meal.self, FoodItem.self,
        StrengthWorkout.self, StrengthSet.self, CardioSession.self,
        NutritionTarget.self, FoodPreset.self, CustomExercise.self, AIReport.self,
    ]
}
