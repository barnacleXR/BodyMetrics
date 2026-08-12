import SwiftUI

/// 记录页顶部的融合卡:左边体重(结果),右边剩余热量(输入),下面三条宏量进度。
///
/// 两个领域并排放在同一张卡上,一眼能看到"吃了多少"与"体重怎么走"——这是把两个 App
/// 合成一个产品最直接的体现。没有营养目标时右半变成设定入口,不用引导页拦住老用户。
struct FusedHeroCard: View {
    let weight: Double?
    let weightTime: Date?
    let deltaVsYesterday: Double?
    let totals: DayTotals
    let target: MacroTotals?
    let remaining: RemainingBudget
    let onSetupTarget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                weightColumn
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1)
                    .padding(.horizontal, 14)
                if target == nil {
                    setupColumn
                } else {
                    energyColumn
                }
            }
            if let target {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.vertical, 14)
                macroBars(target: target)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color("HeroGradientStart"), Color("HeroGradientEnd")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25)
        )
        .shadow(color: Color("BrandGreen").opacity(0.22), radius: 12, y: 6)
    }

    // MARK: - 体重

    private var weightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("体重")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(weight.map { StatsCalculator.format1($0) } ?? "--")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("kg")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 4)
            Text(weightSubtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weightSubtitle: String {
        if let delta = deltaVsYesterday {
            let arrow = delta < 0 ? "↓" : "↑"
            return "\(arrow) \(StatsCalculator.format1(abs(delta))) " + String(localized: "较昨日")
        }
        if weight != nil {
            if let weightTime {
                return weightTime.formatted(.dateTime.hour().minute())
            }
            return String(localized: "首次记录")
        }
        return String(localized: "尚未记录")
    }

    // MARK: - 热量

    private var energyColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(remaining.kcal >= 0 ? "剩余热量" : "已超出")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(abs(remaining.kcal)))")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(remaining.kcal >= 0 ? .white : Color(red: 1, green: 0.85, blue: 0.55))
                Text("kcal")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 4)
            Text("\(String(localized: "已摄入")) \(Int(totals.macros.kcal.rounded())) / \(Int(remaining.budgetKcal))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupColumn: some View {
        Button(action: onSetupTarget) {
            VStack(alignment: .leading, spacing: 6) {
                Text("每日目标")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 5) {
                    Text("设定")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))
                Text("填完档案即可算出")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 宏量进度

    private func macroBars(target: MacroTotals) -> some View {
        HStack(spacing: 12) {
            macroBar(label: String(localized: "蛋白质"), consumed: totals.macros.proteinG, goal: target.proteinG)
            macroBar(label: String(localized: "脂肪"), consumed: totals.macros.fatG, goal: target.fatG)
            macroBar(label: String(localized: "碳水"), consumed: totals.macros.carbG, goal: target.carbG)
        }
    }

    private func macroBar(label: String, consumed: Double, goal: Double) -> some View {
        let ratio = goal > 0 ? min(consumed / goal, 1) : 0
        let over = goal > 0 && consumed > goal
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
                Spacer(minLength: 0)
                Text("\(Int(consumed.rounded()))/\(Int(goal.rounded()))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(over ? Color(red: 1, green: 0.78, blue: 0.42) : Color.white)
                        .frame(width: max(2, proxy.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Int(consumed.rounded())) / \(Int(goal.rounded())) g")
    }
}
