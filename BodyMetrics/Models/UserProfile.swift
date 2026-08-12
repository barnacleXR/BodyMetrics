import Foundation
import SwiftData

/// 用户偏好(单例,App 启动时确保存在)。
///
/// 注意:这里**不存体重**。体重来自 `MetricEntry` 的最新一条记录,
/// 基础代谢与每日目标随实测体重自动更新——手填一个静态体重会让 TDEE 静默失真。
@Model
final class UserProfile {
    var goalWeight: Double = 58.0
    var heightCm: Double = 170.0
    var reminderEnabled: Bool = true
    var biometricLockEnabled: Bool = false

    // MARK: - 身体档案(基础代谢公式需要)

    var sex: Sex = Sex.male
    /// 0 表示未设置。不编造默认出生年:假数据会让 TDEE 失真而界面上看不出来
    var birthYear: Int = 0
    var activityLevel: ActivityLevel = ActivityLevel.sedentary

    // MARK: - 目标与偏好

    /// 每周期望体重变化(kg),负为减重。与目标体重一起推出每日热量目标
    var weeklyRateKg: Double = -0.5
    /// 训练消耗是否回补进当日额度。活动系数已含日常活动,默认关闭以免双重计算
    var addBurnedToBudget: Bool = false
    /// 是否采用自适应 TDEE(由实测体重反推)替代公式估算值
    var useAdaptiveTDEE: Bool = false
    var themePreference: ThemePreference = ThemePreference.system
    /// 被隐藏的内置动作 id
    var hiddenBuiltinExerciseIDs: [String] = []

    init(
        goalWeight: Double = 58.0,
        heightCm: Double = 170.0,
        reminderEnabled: Bool = true,
        biometricLockEnabled: Bool = false,
        sex: Sex = .male,
        birthYear: Int = 0,
        activityLevel: ActivityLevel = .sedentary,
        weeklyRateKg: Double = -0.5,
        addBurnedToBudget: Bool = false,
        useAdaptiveTDEE: Bool = false,
        themePreference: ThemePreference = .system
    ) {
        self.goalWeight = goalWeight
        self.heightCm = heightCm
        self.reminderEnabled = reminderEnabled
        self.biometricLockEnabled = biometricLockEnabled
        self.sex = sex
        self.birthYear = birthYear
        self.activityLevel = activityLevel
        self.weeklyRateKg = weeklyRateKg
        self.addBurnedToBudget = addBurnedToBudget
        self.useAdaptiveTDEE = useAdaptiveTDEE
        self.themePreference = themePreference
    }

    /// 身体档案是否填全(算 TDEE 的前提)
    var hasBodyProfile: Bool {
        birthYear > 1900 && heightCm > 0
    }

    var age: Int? {
        guard birthYear > 1900 else { return nil }
        return Calendar.current.component(.year, from: .now) - birthYear
    }

    var colorScheme: ColorSchemePreference {
        switch themePreference {
        case .system: return .system
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 与 SwiftUI 解耦的配色偏好(视图层转成 ColorScheme?)
enum ColorSchemePreference {
    case system, light, dark
}
