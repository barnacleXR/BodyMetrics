import SwiftUI

/// 试算购物车的一条
struct DraftEntry: Identifiable, Equatable {
    let id = UUID()
    var draft: FoodDraft
    var mealType: MealType
}

/// 试算区:先把想吃的东西堆进来看总账,合适了再一次性记入。
///
/// 解决的是"还没吃、想知道吃了会不会超"这个真实场景——直接记下去再删,
/// 会把历史记录搅乱。
struct DraftBoxView: View {
    let entries: [DraftEntry]
    let remainingBefore: RemainingBudget
    let remainingAfter: RemainingBudget
    let hasTarget: Bool
    let onRemove: (DraftEntry) -> Void
    let onClear: () -> Void
    let onCommit: () -> Void

    private var totalKcal: Double {
        entries.reduce(0) { $0 + $1.draft.macros.kcal }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(
                text: "试算",
                trailing: AnyView(
                    Button(String(localized: "清空"), action: onClear)
                        .font(.system(size: 12))
                        .foregroundStyle(Color("TextSecondary"))
                )
            )
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 14) }
                    row(entry)
                }
                Divider()
                summary
            }
            .background(
                RoundedRectangle(cornerRadius: 17)
                    .fill(Color("CardBackground"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(Color("BrandGreen").opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
        }
    }

    private func row(_ entry: DraftEntry) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.draft.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Color("TextPrimary"))
                    .lineLimit(1)
                Text("\(entry.mealType.label) · \(amountText(entry.draft))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Spacer()
            Text("\(Int(entry.draft.macros.kcal.rounded()))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color("TextPrimary"))
            Button {
                onRemove(entry)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .frame(width: 30, height: 44)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "从试算中移除 \(entry.draft.name)"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 54)
    }

    private func amountText(_ draft: FoodDraft) -> String {
        draft.basis == .per100g
            ? "\(NumberText.text(draft.amount)) g"
            : "\(NumberText.text(draft.amount)) \(draft.servingLabel.isEmpty ? String(localized: "份") : draft.servingLabel)"
    }

    private var summary: some View {
        VStack(spacing: 10) {
            HStack {
                Text("试算 \(entries.count) 项")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
                Text("+\(Int(totalKcal.rounded())) kcal")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color("TextPrimary"))
            }
            if hasTarget {
                HStack {
                    Text("吃完后剩余")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("TextSecondary"))
                    Spacer()
                    Text("\(Int(remainingBefore.kcal)) → \(Int(remainingAfter.kcal))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(remainingAfter.kcal < 0 ? Color(red: 0.72, green: 0.45, blue: 0.1) : Color("BrandGreen"))
                }
            }
            PrimaryButton(title: "记入这一天", systemImage: "checkmark", action: onCommit)
                .frame(height: 44)
        }
        .padding(14)
    }
}
