import Foundation

/// 一次称重(纯值类型,便于单测)
struct WeightSample: Equatable {
    let date: Date
    let kg: Double
}

/// 某一天的能量收支(纯值类型)
struct DailyIntake: Equatable {
    let day: Date
    let intakeKcal: Double
    let burnedKcal: Double
    /// 当天是否真的记了饮食。漏记的日子必须显式标记,不能当作"摄入 0"
    let hasIntakeRecord: Bool
}

/// 能量收支闭环——本次融合的核心。
///
/// 体重是结果,饮食与训练是输入。这一层把两者接起来:
/// 用摄入预测体重(F2)、用实测体重反推真实代谢(F3)、由目标体重推出每日热量目标(F4)。
/// 这三件事都**只有在两份数据位于同一个 App 时才可能实现**。
enum EnergyBalanceService {

    /// 1 kg 体重变化约等于 7700 kcal 能量差额(脂肪组织的常用近似值)
    static let kcalPerKg: Double = 7700

    // MARK: - F2 由摄入预测体重

    struct ProjectedPoint: Equatable {
        let day: Date
        let kg: Double
    }

    /// 从起始体重出发,按每日净差额累计出预测体重曲线。
    ///
    /// 缺记录的日子会被跳过(不累计也不断言当天摄入为 0),因为把漏记当成"没吃"
    /// 会让预测线一路向下,做出完全失真的结论。
    static func projectedWeights(
        startWeightKg: Double,
        intakes: [DailyIntake],
        tdeeFor: (Date) -> Double,
        addBurnedToBudget: Bool,
        calendar: Calendar = .current
    ) -> [ProjectedPoint] {
        guard startWeightKg > 0 else { return [] }
        var weight = startWeightKg
        var points: [ProjectedPoint] = []
        for intake in intakes.sorted(by: { $0.day < $1.day }) {
            guard intake.hasIntakeRecord else { continue }
            let expenditure = tdeeFor(intake.day) + (addBurnedToBudget ? 0 : intake.burnedKcal)
            weight += (intake.intakeKcal - expenditure) / kcalPerKg
            points.append(ProjectedPoint(day: calendar.startOfDay(for: intake.day), kg: weight))
        }
        return points
    }

    // MARK: - F3 由实测体重反推真实代谢

    enum AdaptiveTDEE: Equatable {
        /// 数据不足,不给数字。给错数字比不给更危险
        case insufficientData(reason: String)
        /// 算出来了但偏离公式值太远,标为不可信
        case unreliable(kcal: Double, formulaKcal: Double)
        case available(kcal: Double, formulaKcal: Double)

        var kcal: Double? {
            switch self {
            case .available(let kcal, _): return kcal
            case .unreliable, .insufficientData: return nil
            }
        }
    }

    /// 准入门槛:窗口内至少这么多天有完整摄入记录
    static let minimumLoggedDays = 20
    /// 准入门槛:首尾各 7 日窗口内至少这么多次称重
    static let minimumWeighInsPerEdge = 3
    /// 分析窗口长度
    static let windowDays = 28

    /// 用近 28 天的实测体重变化反推真实 TDEE。
    ///
    ///     adaptiveTDEE = 日均摄入 − 每日体重变化 × 7700
    ///
    /// 用**速率**而非总量:体重变化取首尾各 7 日移动平均之差,而这两个均值代表的是各自
    /// 窗口的**质心时刻**(约相距 21 天),不是整个 28 天。拿 28 天的摄入总量去配 21 天
    /// 跨度的体重变化会系统性地把结果算偏,所以两边都化成"每天多少"再相减。
    /// 质心按实际称重日期计算,称重不规律时也不会失准。
    ///
    /// 体重变化不用单点:单日体重的水分波动可以轻易达到 ±1 kg,直接取两个端点会把噪声
    /// 放大成几百 kcal 的误差。
    ///
    /// 最危险的失效模式是漏记饮食:摄入偏低会把 TDEE 反推得虚低,用户照此加大缺口
    /// 就会越吃越少。下面的准入门槛与合理性钳制就是为此,不要放宽。
    static func adaptiveTDEE(
        weights: [WeightSample],
        intakes: [DailyIntake],
        formulaTDEE: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AdaptiveTDEE {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else {
            return .insufficientData(reason: String(localized: "无法计算分析窗口"))
        }

        let logged = intakes.filter {
            $0.hasIntakeRecord && calendar.startOfDay(for: $0.day) >= windowStart && calendar.startOfDay(for: $0.day) <= today
        }
        guard logged.count >= minimumLoggedDays else {
            let missing = minimumLoggedDays - logged.count
            return .insufficientData(
                reason: String(localized: "近 28 天还需 \(missing) 天的完整饮食记录")
            )
        }

        // 首尾各 7 日窗口
        guard let firstEdgeEnd = calendar.date(byAdding: .day, value: 6, to: windowStart),
              let lastEdgeStart = calendar.date(byAdding: .day, value: -6, to: today)
        else {
            return .insufficientData(reason: String(localized: "无法计算分析窗口"))
        }

        let firstEdge = weights.filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= windowStart && d <= firstEdgeEnd
        }
        let lastEdge = weights.filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= lastEdgeStart && d <= today
        }
        guard firstEdge.count >= minimumWeighInsPerEdge, lastEdge.count >= minimumWeighInsPerEdge else {
            return .insufficientData(
                reason: String(localized: "分析窗口首尾各需至少 3 次称重")
            )
        }

        guard let start = centroid(of: firstEdge, calendar: calendar),
              let end = centroid(of: lastEdge, calendar: calendar)
        else {
            return .insufficientData(reason: String(localized: "称重数据不足"))
        }

        // 两个均值各自代表其窗口的质心时刻,间距才是体重变化真正跨越的天数
        let spanDays = end.date.timeIntervalSince(start.date) / 86_400
        guard spanDays >= 7 else {
            return .insufficientData(reason: String(localized: "两次称重的时间跨度太短"))
        }

        let dailyWeightChange = (end.kg - start.kg) / spanDays
        let averageIntake = logged.reduce(0) { $0 + $1.intakeKcal } / Double(logged.count)
        let estimate = averageIntake - dailyWeightChange * kcalPerKg

        guard estimate > 0 else {
            return .insufficientData(reason: String(localized: "数据不足以得出可信结论"))
        }
        // 合理性钳制:偏离公式估算过远,多半是记录不全而不是代谢异常
        if formulaTDEE > 0, estimate < formulaTDEE * 0.6 || estimate > formulaTDEE * 1.6 {
            return .unreliable(kcal: estimate.rounded(), formulaKcal: formulaTDEE)
        }
        return .available(kcal: estimate.rounded(), formulaKcal: formulaTDEE)
    }

    // MARK: - F4 由目标体重推出每日热量目标

    struct TargetPlan: Equatable {
        var tdeeKcal: Double
        var bmrKcal: Double
        /// 每日热量差额(减重为负)
        var dailyDeltaKcal: Double
        var targetKcal: Double
        var macros: MacroTotals
        /// 目标热量被 BMR 下限钳制过——用户设的减重速度过激
        var wasClampedToBMR: Bool
        /// 这份目标**实际**能带来的每周变化。未钳制时等于用户设定值;
        /// 钳制后会小于设定值,界面必须按这个说话,不能拿用户的一厢情愿当结论
        var achievableWeeklyRateKg: Double
        /// 按可达成速度预计达成目标体重的日期;速度为 0 或方向不对时为 nil
        var estimatedGoalDate: Date?
    }

    /// 目标体重 + 每周期望变化 → 每日热量与宏量目标 + 预计达成日期。
    ///
    /// 用户不需要分别设定"目标体重"和"每日吃多少",后者由前者推出——这是两个
    /// 领域合成一个目标体系的地方。
    static func plan(
        sex: Sex,
        currentWeightKg: Double,
        goalWeightKg: Double,
        heightCm: Double,
        age: Int,
        activityLevel: ActivityLevel,
        weeklyRateKg: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TargetPlan? {
        guard currentWeightKg > 0, heightCm > 0, age > 0 else { return nil }

        let bmr = NutritionCalculator.bmr(sex: sex, weightKg: currentWeightKg, heightCm: heightCm, age: age)
        let tdee = NutritionCalculator.tdee(
            sex: sex, weightKg: currentWeightKg, heightCm: heightCm,
            age: age, activityLevel: activityLevel
        )
        guard tdee > 0 else { return nil }

        let dailyDelta = weeklyRateKg * kcalPerKg / 7
        let raw = tdee + dailyDelta
        // 安全下限:目标热量不得低于基础代谢。
        // 久坐者的 TDEE 与 BMR 相差有限,设一个激进的减重速度很容易触发这里——
        // 这不是 bug,而是在说"光靠吃少达不到这个速度"
        let clamped = raw < bmr
        let target = clamped ? bmr : raw

        // 钳制后实际能达成的速度,由真正生效的热量差额倒推
        let achievableRate = clamped ? (target - tdee) * 7 / kcalPerKg : weeklyRateKg

        return TargetPlan(
            tdeeKcal: tdee,
            bmrKcal: bmr,
            dailyDeltaKcal: dailyDelta.rounded(),
            targetKcal: target.rounded(),
            macros: NutritionCalculator.macros(forKcal: target, weightKg: currentWeightKg),
            wasClampedToBMR: clamped,
            achievableWeeklyRateKg: NutritionCalculator.round1(achievableRate),
            // 用可达成速度而非用户设定值:目标被钳制后还按原速度报达成日期就是在给假承诺
            estimatedGoalDate: estimatedGoalDate(
                currentWeightKg: currentWeightKg,
                goalWeightKg: goalWeightKg,
                weeklyRateKg: achievableRate,
                now: now,
                calendar: calendar
            )
        )
    }

    /// 预计达成日期。速度为 0、已达成、或速度方向与目标相反时返回 nil
    static func estimatedGoalDate(
        currentWeightKg: Double,
        goalWeightKg: Double,
        weeklyRateKg: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard abs(weeklyRateKg) > 0.01 else { return nil }
        let gap = goalWeightKg - currentWeightKg
        guard abs(gap) > 0.05 else { return nil }
        let weeks = gap / weeklyRateKg
        // 方向不对(想减重却设了增重速度)时不给一个负的日期
        guard weeks > 0 else { return nil }
        let days = Int((weeks * 7).rounded())
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
    }

    // MARK: - 工具

    /// 按日取最新一条后求均值(同日多次称重不重复加权)
    static func dailyLatestMean(_ samples: [WeightSample], calendar: Calendar = .current) -> Double? {
        centroid(of: samples, calendar: calendar)?.kg
    }

    /// 一组称重的质心:平均体重,以及这些体重所对应的平均时刻。
    /// 同日多次称重按当日最新一条计,不重复加权
    static func centroid(of samples: [WeightSample], calendar: Calendar = .current) -> (kg: Double, date: Date)? {
        let latestPerDay = Dictionary(grouping: samples, by: { calendar.startOfDay(for: $0.date) })
            .compactMap { day, sameDay -> (Date, Double)? in
                guard let latest = sameDay.max(by: { $0.date < $1.date }) else { return nil }
                return (day, latest.kg)
            }
        guard !latestPerDay.isEmpty else { return nil }
        let count = Double(latestPerDay.count)
        let meanKg = latestPerDay.reduce(0) { $0 + $1.1 } / count
        let meanTime = latestPerDay.reduce(0.0) { $0 + $1.0.timeIntervalSinceReferenceDate } / count
        return (meanKg, Date(timeIntervalSinceReferenceDate: meanTime))
    }
}
