import Foundation
import SwiftData

/// 用户自定义动作。录入一个内置库里没有的动作名时自动入库,否则下次搜不到、要重打全名。
@Model
final class CustomExercise {
    var name: String = ""
    var kind: ExerciseKind = ExerciseKind.strength
    /// 部位分组(力量),有氧统一为"有氧"
    var group: String = ""

    init(name: String, kind: ExerciseKind, group: String = "") {
        self.name = name
        self.kind = kind
        self.group = group
    }
}
