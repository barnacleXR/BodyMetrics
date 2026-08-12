import SwiftUI
import SwiftData

/// 目标设定:身体档案 + 目标体重 + 每周期望变化 → 实时推出每日热量与宏量目标。
///
/// 用户只说"想到多重"和"多快",每天吃多少由系统推出来——两个领域在这里合成
/// 一个目标体系,而不是让人各填一套互不相干的数字。
struct NutritionGoalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var profiles: [UserProfile]

    @State private var sex: Sex = .male
    @State private var birthYearText = ""
    @State private var heightText = ""
    @State private var goalWeightText = ""
    @State private var weeklyRate: Double = -0.5
    @State private var activityLevel: ActivityLevel = .sedentary
    @State private var manualOverride = false
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbText = ""
    @State private var didPrefill = false

    private var profile: UserProfile? { profiles.first }

    private var latestWeight: Double? {
        entries.filter { $0.metric == .weight }.max(by: { $0.date < $1.date })?.value
    }

    private var age: Int? {
        let year = Int(birthYearText)
        guard let year, year > 1900 else { return nil }
        return Calendar.current.component(.year, from: .now) - year
    }

    private var plan: EnergyBalanceService.TargetPlan? {
        guard let weight = latestWeight, let age,
              let height = Double(heightText), height > 0,
              let goal = Double(goalWeightText), goal > 0
        else { return nil }
        return EnergyBalanceService.plan(
            sex: sex, currentWeightKg: weight, goalWeightKg: goal,
            heightCm: height, age: age, activityLevel: activityLevel,
            weeklyRateKg: weeklyRate
        )
    }

    /// 实际写入的目标:手动覆盖时用输入框的值,否则用推算值
    private var effectiveMacros: MacroTotals? {
        guard let plan else { return nil }
        guard manualOverride else { return plan.macros }
        return MacroTotals(
            kcal: NumberText.value(kcalText),
            proteinG: NumberText.value(proteinText),
            fatG: NumberText.value(fatText),
            carbG: NumberText.value(carbText)
        )
    }

    private let rateOptions: [Double] = [-1.0, -0.75, -0.5, -0.25, 0, 0.25, 0.5]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "每日目标") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if latestWeight == nil {
                        noWeightHint
                    }
                    bodyProfileSection
                    goalSection
                    if let plan {
                        previewSection(plan)
                    } else {
                        EmptyHint(text: "把出生年、身高、目标体重填完就能算出每日目标。")
                            .cardBackground()
                            .padding(.bottom, 16)
                    }
                    PrimaryButton(title: "保存为今天起生效", enabled: effectiveMacros != nil, action: save)
                    Text("改目标只影响今天起的日子,历史达标情况不会被重写。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineSpacing(3)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 23)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear(perform: prefill)
    }

    // MARK: - 分区

    private var noWeightHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "scalemass")
                .font(.system(size: 14))
                .foregroundStyle(Color("TextSecondary"))
            Text("还没有体重记录。基础代谢按实测体重计算,先记一条体重才能算出目标。")
                .font(.system(size: 12))
                .foregroundStyle(Color("TextSecondary"))
                .lineSpacing(3)
        }
        .padding(14)
        .cardBackground(cornerRadius: 13)
        .padding(.bottom, 16)
    }

    private var bodyProfileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "身体档案")
            VStack(alignment: .leading, spacing: 0) {
                LabeledField(label: "性别(基础代谢公式需要)") {
                    Picker("", selection: $sex) {
                        ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack(spacing: 10) {
                    LabeledField(label: "出生年") {
                        DecimalField(placeholder: "1995", text: $birthYearText)
                    }
                    LabeledField(label: "身高") {
                        DecimalField(placeholder: "172", text: $heightText, unit: "cm")
                    }
                }
                LabeledField(label: "活动强度") {
                    Picker("", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text("\(level.label) ×\(StatsCalculator.format1(level.factor))").tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color("TextPrimary"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color("CardBackground"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Color("TextSecondary").opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                Text(currentWeightLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
                    .padding(.bottom, 4)
            }
            .padding(14)
            .cardBackground()
            .padding(.bottom, 18)
        }
    }

    private var currentWeightLine: String {
        guard let latestWeight else { return String(localized: "体重取自最新一条记录") }
        return String(localized: "当前体重 \(StatsCalculator.format1(latestWeight)) kg(取自最新记录,不需手填)")
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "目标")
            VStack(alignment: .leading, spacing: 0) {
                LabeledField(label: "目标体重") {
                    DecimalField(placeholder: "58", text: $goalWeightText, unit: "kg")
                }
                LabeledField(label: "每周期望变化") {
                    Picker("", selection: $weeklyRate) {
                        ForEach(rateOptions, id: \.self) { rate in
                            Text(rateLabel(rate)).tag(rate)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color("TextPrimary"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color("CardBackground"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Color("TextSecondary").opacity(0.25), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(14)
            .cardBackground()
            .padding(.bottom, 18)
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        if rate == 0 { return String(localized: "维持体重") }
        let sign = rate < 0 ? "−" : "+"
        return "\(sign)\(StatsCalculator.format1(abs(rate))) kg / \(String(localized: "周"))"
    }

    private func previewSection(_ plan: EnergyBalanceService.TargetPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "推算结果")
            VStack(alignment: .leading, spacing: 0) {
                previewRow(label: String(localized: "每日总消耗 TDEE"),
                           value: "\(Int(plan.tdeeKcal)) kcal")
                Divider().padding(.vertical, 9)
                previewRow(label: String(localized: "每日热量目标"),
                           value: "\(Int(plan.targetKcal)) kcal",
                           emphasized: true)
                Divider().padding(.vertical, 9)
                previewRow(label: String(localized: "三大宏量"),
                           value: plan.macros.compactSummaryText)
                if let goalDate = plan.estimatedGoalDate {
                    Divider().padding(.vertical, 9)
                    previewRow(label: String(localized: "预计达成"),
                               value: goalDate.formatted(.dateTime.year().month().day()))
                }

                if plan.wasClampedToBMR {
                    clampWarning(plan)
                }
            }
            .padding(14)
            .cardBackground()
            .padding(.bottom, 16)

            manualOverrideSection(plan)
        }
    }

    private func previewRow(label: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
            Text(value)
                .font(.system(size: emphasized ? 15 : 13, weight: emphasized ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(Color("TextPrimary"))
        }
    }

    /// 目标被基础代谢下限钳住时,必须照实说"这个速度光靠吃少达不到",
    /// 而不是默默把日期按用户的一厢情愿算出来
    private func clampWarning(_ plan: EnergyBalanceService.TargetPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 9)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.1))
                Text("已按基础代谢下限收住")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.1))
            }
            Text("你设的速度需要每天少吃 \(Int(abs(plan.dailyDeltaKcal))) kcal,会低于基础代谢 \(Int(plan.bmrKcal)) kcal。目标已收在基础代谢上,靠饮食实际能达到的速度约 \(StatsCalculator.format1(plan.achievableWeeklyRateKg)) kg/周。想更快就得靠增加活动量,不是再少吃。")
                .font(.system(size: 11))
                .foregroundStyle(Color("TextSecondary"))
                .lineSpacing(3)
        }
    }

    private func manualOverrideSection(_ plan: EnergyBalanceService.TargetPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $manualOverride) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("手动调整")
                        .font(.system(size: 14))
                    Text("推算值只是起点,可以按自己的经验改")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .tint(Color("BrandGreen"))
            .padding(14)
            .cardBackground()
            .onChange(of: manualOverride) { _, isOn in
                guard isOn else { return }
                kcalText = NumberText.text(plan.macros.kcal)
                proteinText = NumberText.text(plan.macros.proteinG)
                fatText = NumberText.text(plan.macros.fatG)
                carbText = NumberText.text(plan.macros.carbG)
            }

            if manualOverride {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        LabeledField(label: "热量") { DecimalField(text: $kcalText, unit: "kcal") }
                        LabeledField(label: "蛋白质") { DecimalField(text: $proteinText, unit: "g") }
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "脂肪") { DecimalField(text: $fatText, unit: "g") }
                        LabeledField(label: "碳水") { DecimalField(text: $carbText, unit: "g") }
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(.bottom, 18)
    }

    // MARK: - 读写

    private func prefill() {
        guard !didPrefill, let profile else { didPrefill = true; return }
        didPrefill = true
        sex = profile.sex
        birthYearText = profile.birthYear > 1900 ? String(profile.birthYear) : ""
        heightText = NumberText.text(profile.heightCm)
        goalWeightText = NumberText.text(profile.goalWeight)
        weeklyRate = rateOptions.min { abs($0 - profile.weeklyRateKg) < abs($1 - profile.weeklyRateKg) } ?? -0.5
        activityLevel = profile.activityLevel
    }

    private func save() {
        guard let macros = effectiveMacros, let profile else { return }
        profile.sex = sex
        profile.birthYear = Int(birthYearText) ?? 0
        profile.heightCm = Double(heightText) ?? profile.heightCm
        profile.goalWeight = Double(goalWeightText) ?? profile.goalWeight
        profile.weeklyRateKg = weeklyRate
        profile.activityLevel = activityLevel
        try? context.save()

        TargetPlanService.saveTarget(macros, in: context)
        dismiss()
    }
}
