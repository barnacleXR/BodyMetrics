import Foundation
import SwiftData

/// 一餐(早/午/晚/加餐),同一天同一餐次只应有一条
@Model
final class Meal {
    var type: MealType = MealType.breakfast
    var dayLog: DayLog?

    @Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
    var items: [FoodItem] = []

    init(type: MealType) {
        self.type = type
    }
}
