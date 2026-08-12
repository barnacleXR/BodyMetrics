import Foundation
import SwiftData

/// 目标体系的读写。把 UserProfile + 最新体重接到 EnergyBalanceService 上,
/// 并负责把算出来的目标落成一条版本化的 NutritionTarget
enum TargetPlanService {

    /// 由档案与最新体重算出当前方案。档案不全时返回 nil(不编数字)
    static func currentPlan(
        profile: UserProfile,
        entries: [MetricEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> EnergyBalanceService.TargetPlan? {
        guard let weight = StatsCalculator.latestValue(on: now, metric: .weight, in: entries, calendar: calendar)
                ?? entries.filter({ $0.metric == .weight }).max(by: { $0.date < $1.date })?.value
        else { return nil }
        guard let age = profile.age else { return nil }

        return EnergyBalanceService.plan(
            sex: profile.sex,
            currentWeightKg: weight,
            goalWeightKg: profile.goalWeight,
            heightCm: profile.heightCm,
            age: age,
            activityLevel: profile.activityLevel,
            weeklyRateKg: profile.weeklyRateKg,
            now: now,
            calendar: calendar
        )
    }

    /// 保存一条从今天起生效的目标。
    /// 同一天重复保存只更新那一条,不堆出一串同日目标
    static func saveTarget(
        _ macros: MacroTotals,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let today = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<NutritionTarget>(predicate: #Predicate { $0.effectiveFrom == today })
        if let existing = try? context.fetch(descriptor).first {
            existing.kcal = macros.kcal
            existing.proteinG = macros.proteinG
            existing.fatG = macros.fatG
            existing.carbG = macros.carbG
        } else {
            context.insert(NutritionTarget(
                effectiveFrom: today,
                kcal: macros.kcal, proteinG: macros.proteinG,
                fatG: macros.fatG, carbG: macros.carbG
            ))
        }
        try? context.save()
    }

    /// 是否已经设过营养目标
    static func hasAnyTarget(in context: ModelContext) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<NutritionTarget>())) ?? 0) > 0
    }
}
