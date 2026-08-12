import SwiftUI

/// 自适应 TDEE 卡片——本次融合最核心的产出。
///
/// 用实测体重反推真实代谢,和公式估算值放在一起比。这个数字只有在体重与
/// 饮食记录位于同一个 App 时才算得出来。数据不足时**只说不足,不给数字**:
/// 给一个错的代谢值会让人照着它加大缺口,越吃越少。
struct AdaptiveTDEECard: View {
    let result: EnergyBalanceService.AdaptiveTDEE
    let isAdopted: Bool
    let onAdopt: () -> Void
    let onRevert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                    .foregroundStyle(Color("BrandGreen"))
                Text("实测代谢")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .insufficientData(let reason):
            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(Color("TextSecondary"))
                .lineSpacing(3)
            Text("记满之后这里会用你的实际体重变化反推真实代谢,和公式估算对比。")
                .font(.system(size: 11))
                .foregroundStyle(Color("TextSecondary"))
                .lineSpacing(3)

        case .unreliable(let kcal, let formula):
            comparison(measured: kcal, formula: formula)
            Text("这个结果和公式估算差得太远,多半是某几天漏记了饮食,而不是代谢异常。先把记录补齐再看。")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.1))
                .lineSpacing(3)

        case .available(let kcal, let formula):
            comparison(measured: kcal, formula: formula)
            Text(deltaDescription(measured: kcal, formula: formula))
                .font(.system(size: 11))
                .foregroundStyle(Color("TextSecondary"))
                .lineSpacing(3)
            if isAdopted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("BrandGreen"))
                    Text("已按实测代谢计算目标")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("BrandGreen"))
                    Spacer()
                    Button(String(localized: "改回公式值"), action: onRevert)
                        .font(.system(size: 12))
                        .foregroundStyle(Color("TextSecondary"))
                }
                .padding(.top, 2)
            } else {
                GhostButton(title: "采用实测值重算目标", systemImage: "arrow.triangle.2.circlepath", action: onAdopt)
                    .padding(.top, 2)
            }
        }
    }

    private func comparison(measured: Double, formula: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("公式估算")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("TextSecondary"))
                Text("\(Int(formula))")
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("你的实测")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("TextSecondary"))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(measured))")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color("TextPrimary"))
                    Text("kcal")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            Spacer()
        }
    }

    private func deltaDescription(measured: Double, formula: Double) -> String {
        guard formula > 0 else { return "" }
        let percent = Int(((measured - formula) / formula * 100).rounded())
        if abs(percent) < 3 {
            return String(localized: "和公式估算基本一致,说明活动强度选得准。")
        }
        return percent > 0
            ? String(localized: "比公式估算高 \(abs(percent))%,你的日常活动量比所选强度更大。")
            : String(localized: "比公式估算低 \(abs(percent))%,按公式设的目标可能偏松。")
    }
}
