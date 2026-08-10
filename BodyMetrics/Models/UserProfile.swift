import Foundation
import SwiftData

/// 用户偏好(单例,App 启动时确保存在)
@Model
final class UserProfile {
    var goalWeight: Double = 58.0
    var heightCm: Double = 170.0
    var reminderEnabled: Bool = true
    var biometricLockEnabled: Bool = false

    init(
        goalWeight: Double = 58.0,
        heightCm: Double = 170.0,
        reminderEnabled: Bool = true,
        biometricLockEnabled: Bool = false
    ) {
        self.goalWeight = goalWeight
        self.heightCm = heightCm
        self.reminderEnabled = reminderEnabled
        self.biometricLockEnabled = biometricLockEnabled
    }
}
