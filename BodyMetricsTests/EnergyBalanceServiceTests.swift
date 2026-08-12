import Testing
import Foundation
@testable import BodyMetrics

/// 融合核心的测试。这里的每一条都对应「两份数据不在同一个 App 里就做不出来」的能力
struct EnergyBalanceServiceTests {

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    // MARK: - F2 由摄入预测体重

    @Test func deficitProjectsWeightDown() {
        // 每天缺口 770 kcal,10 天应当掉 770×10/7700 = 1.0 kg
        let intakes = ((-9)...0).map {
            DailyIntake(day: day($0), intakeKcal: 1230, burnedKcal: 0, hasIntakeRecord: true)
        }
        let points = EnergyBalanceService.projectedWeights(
            startWeightKg: 70,
            intakes: intakes,
            tdeeFor: { _ in 2000 },
            addBurnedToBudget: false
        )
        #expect(points.count == 10)
        #expect(abs(points.last!.kg - 69.0) < 0.0001)
    }

    @Test func missingDaysAreSkippedNotTreatedAsZeroIntake() {
        // 中间 5 天没记录。若把漏记当成"没吃",预测线会一路暴跌,给出完全失真的结论
        var intakes = ((-9)...(-5)).map {
            DailyIntake(day: day($0), intakeKcal: 1230, burnedKcal: 0, hasIntakeRecord: true)
        }
        intakes += ((-4)...0).map {
            DailyIntake(day: day($0), intakeKcal: 0, burnedKcal: 0, hasIntakeRecord: false)
        }
        let points = EnergyBalanceService.projectedWeights(
            startWeightKg: 70,
            intakes: intakes,
            tdeeFor: { _ in 2000 },
            addBurnedToBudget: false
        )
        // 只有 5 天进入累计,掉 0.5 kg;而不是把 5 天当作各缺口 2000 kcal
        #expect(points.count == 5)
        #expect(abs(points.last!.kg - 69.5) < 0.0001)
    }

    @Test func burnedCaloriesCountAsExpenditureWhenNotRefunded() {
        // 不回补额度时,训练消耗是真实支出,要算进预测
        let intakes = [DailyIntake(day: day(0), intakeKcal: 2000, burnedKcal: 770, hasIntakeRecord: true)]
        let refunded = EnergyBalanceService.projectedWeights(
            startWeightKg: 70, intakes: intakes, tdeeFor: { _ in 2000 }, addBurnedToBudget: true
        )
        let notRefunded = EnergyBalanceService.projectedWeights(
            startWeightKg: 70, intakes: intakes, tdeeFor: { _ in 2000 }, addBurnedToBudget: false
        )
        #expect(abs(refunded.last!.kg - 70.0) < 0.0001)
        #expect(abs(notRefunded.last!.kg - 69.9) < 0.0001)
    }

    // MARK: - F3 自适应 TDEE

    /// 造一段"真实 TDEE 已知"的数据:固定摄入,体重按能量差额线性变化
    private func syntheticData(
        trueTDEE: Double,
        intake: Double,
        startWeight: Double = 70,
        loggedDays: Int = 28,
        weighInEveryDays: Int = 1
    ) -> (weights: [WeightSample], intakes: [DailyIntake]) {
        let dailyChange = (intake - trueTDEE) / EnergyBalanceService.kcalPerKg
        var weights: [WeightSample] = []
        var intakes: [DailyIntake] = []
        for offset in stride(from: -27, through: 0, by: 1) {
            let index = offset + 27
            let logged = index < loggedDays
            intakes.append(DailyIntake(
                day: day(offset),
                intakeKcal: logged ? intake : 0,
                burnedKcal: 0,
                hasIntakeRecord: logged
            ))
            if index % weighInEveryDays == 0 {
                weights.append(WeightSample(
                    date: day(offset),
                    kg: startWeight + dailyChange * Double(index)
                ))
            }
        }
        return (weights, intakes)
    }

    @Test func adaptiveTDEERecoversKnownMetabolism() {
        let data = syntheticData(trueTDEE: 2400, intake: 2000)
        let result = EnergyBalanceService.adaptiveTDEE(
            weights: data.weights, intakes: data.intakes, formulaTDEE: 2300
        )
        guard case .available(let kcal, _) = result else {
            Issue.record("应当算得出结果,实际是 \(result)")
            return
        }
        // 用速率形式(质心间距)反推,应当精确还原,不受 28 天与 21 天跨度不一致的系统偏差影响
        #expect(abs(kcal - 2400) <= 1)
    }

    @Test func adaptiveTDEERecoversMetabolismWithIrregularWeighIns() {
        // 每 3 天才称一次,质心按实际称重日期算,结果仍应准确
        let data = syntheticData(trueTDEE: 2600, intake: 2200, weighInEveryDays: 3)
        let result = EnergyBalanceService.adaptiveTDEE(
            weights: data.weights, intakes: data.intakes, formulaTDEE: 2500
        )
        guard case .available(let kcal, _) = result else {
            Issue.record("应当算得出结果,实际是 \(result)")
            return
        }
        #expect(abs(kcal - 2600) <= 5)
    }

    @Test func adaptiveTDEERefusesWhenIntakeLoggingIsSparse() {
        // 只记了 15 天。漏记会让摄入偏低、TDEE 被反推得虚低,此时必须拒绝给数字
        let data = syntheticData(trueTDEE: 2400, intake: 2000, loggedDays: 15)
        let result = EnergyBalanceService.adaptiveTDEE(
            weights: data.weights, intakes: data.intakes, formulaTDEE: 2300
        )
        guard case .insufficientData = result else {
            Issue.record("记录不全时不能给出数字,实际是 \(result)")
            return
        }
    }

    @Test func adaptiveTDEERefusesWhenEdgesLackWeighIns() {
        var data = syntheticData(trueTDEE: 2400, intake: 2000)
        // 抹掉最近 7 天的称重:没有末端锚点就无从判断体重去向
        data.weights.removeAll { $0.date > day(-7) }
        let result = EnergyBalanceService.adaptiveTDEE(
            weights: data.weights, intakes: data.intakes, formulaTDEE: 2300
        )
        guard case .insufficientData = result else {
            Issue.record("首尾缺称重时不能给出数字,实际是 \(result)")
            return
        }
    }

    @Test func adaptiveTDEEFlagsImplausibleResults() {
        // 摄入极低而体重几乎没动 → 反推出的代谢低得不合理,应标为不可信而非照单全收
        var intakes: [DailyIntake] = []
        var weights: [WeightSample] = []
        for offset in stride(from: -27, through: 0, by: 1) {
            intakes.append(DailyIntake(day: day(offset), intakeKcal: 900, burnedKcal: 0, hasIntakeRecord: true))
            weights.append(WeightSample(date: day(offset), kg: 70))
        }
        let result = EnergyBalanceService.adaptiveTDEE(
            weights: weights, intakes: intakes, formulaTDEE: 2400
        )
        guard case .unreliable = result else {
            Issue.record("离谱结果必须标为不可信,实际是 \(result)")
            return
        }
        #expect(result.kcal == nil)
    }

    // MARK: - F4 目标体重 → 每日热量目标

    @Test func planDerivesTargetFromWeeklyRate() {
        let plan = EnergyBalanceService.plan(
            sex: .male, currentWeightKg: 70, goalWeightKg: 65, heightCm: 175,
            age: 30, activityLevel: .moderate, weeklyRateKg: -0.5
        )
        guard let plan else {
            Issue.record("档案完整时应当算得出方案")
            return
        }
        // −0.5 kg/周 → 每天缺口 −0.5 × 7700 ÷ 7 = −550
        #expect(plan.dailyDeltaKcal == -550)
        #expect(plan.targetKcal == (plan.tdeeKcal - 550).rounded())
        #expect(!plan.wasClampedToBMR)
        #expect(plan.achievableWeeklyRateKg == -0.5)
        #expect(plan.macros.proteinG == 112)
    }

    @Test func sedentaryUserCannotReachHalfKiloPerWeekByDietAlone() {
        // 久坐者 TDEE(1979)与 BMR(1649)只差 330 kcal,−0.5 kg/周 需要 550 的缺口。
        // 这时钳制到 BMR 是正确行为:它在说"光靠吃少达不到这个速度"
        let plan = EnergyBalanceService.plan(
            sex: .male, currentWeightKg: 70, goalWeightKg: 65, heightCm: 175,
            age: 30, activityLevel: .sedentary, weeklyRateKg: -0.5
        )!
        #expect(plan.wasClampedToBMR)
        #expect(plan.targetKcal == plan.bmrKcal)
        // 实际能达成的速度约 −0.3 kg/周,而不是用户设的 −0.5
        #expect(abs(plan.achievableWeeklyRateKg - (-0.3)) < 0.05)
    }

    @Test func goalDateFollowsAchievableRateNotTheRequestedOne() {
        // 目标被钳制后仍按用户设定的速度报达成日期,等于给一个永远兑现不了的承诺
        let plan = EnergyBalanceService.plan(
            sex: .male, currentWeightKg: 70, goalWeightKg: 65, heightCm: 175,
            age: 30, activityLevel: .sedentary, weeklyRateKg: -0.5
        )!
        let honest = EnergyBalanceService.estimatedGoalDate(
            currentWeightKg: 70, goalWeightKg: 65, weeklyRateKg: plan.achievableWeeklyRateKg
        )
        let wishful = EnergyBalanceService.estimatedGoalDate(
            currentWeightKg: 70, goalWeightKg: 65, weeklyRateKg: -0.5
        )
        #expect(plan.estimatedGoalDate == honest)
        #expect(plan.estimatedGoalDate != wishful)
    }

    @Test func planClampsAggressiveDeficitToBMR() {
        // −2 kg/周 → 每天缺口 2200 kcal,会把目标压到基础代谢之下
        let plan = EnergyBalanceService.plan(
            sex: .female, currentWeightKg: 55, goalWeightKg: 48, heightCm: 160,
            age: 35, activityLevel: .sedentary, weeklyRateKg: -2.0
        )
        guard let plan else {
            Issue.record("档案完整时应当算得出方案")
            return
        }
        #expect(plan.wasClampedToBMR)
        #expect(plan.targetKcal == plan.bmrKcal)
    }

    @Test func planReturnsNilWithoutBodyProfile() {
        // 出生年未设置(age 0)时不能编一个目标出来
        #expect(EnergyBalanceService.plan(
            sex: .male, currentWeightKg: 70, goalWeightKg: 65, heightCm: 175,
            age: 0, activityLevel: .sedentary, weeklyRateKg: -0.5
        ) == nil)
    }

    // MARK: - 预计达成日期

    @Test func goalDateProjectsFromRate() {
        // 差 5 kg,每周 −0.5 kg → 10 周 = 70 天
        let date = EnergyBalanceService.estimatedGoalDate(
            currentWeightKg: 70, goalWeightKg: 65, weeklyRateKg: -0.5
        )
        #expect(date == calendar.date(byAdding: .day, value: 70, to: today))
    }

    @Test func goalDateIsNilWhenUnreachable() {
        // 想减重却设了增重速度:不能给一个负数日期
        #expect(EnergyBalanceService.estimatedGoalDate(
            currentWeightKg: 70, goalWeightKg: 65, weeklyRateKg: 0.5
        ) == nil)
        // 速度为 0 永远到不了
        #expect(EnergyBalanceService.estimatedGoalDate(
            currentWeightKg: 70, goalWeightKg: 65, weeklyRateKg: 0
        ) == nil)
        // 已经达成
        #expect(EnergyBalanceService.estimatedGoalDate(
            currentWeightKg: 65, goalWeightKg: 65, weeklyRateKg: -0.5
        ) == nil)
    }
}
