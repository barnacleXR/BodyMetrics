import SwiftUI

/// 力量训练录入表单
struct StrengthFormView: View {
    var initial: StrengthDraft?
    var onSubmit: (StrengthDraft) -> Void
    var onDelete: (() -> Void)?

    @State private var name = ""
    @State private var sets: [SetRow] = [SetRow()]
    @State private var kcalText = ""
    @State private var kcalSource: KcalSource = .manual
    @State private var didPrefill = false

    /// 表单内的一组(文本态,提交时才转成数值)
    private struct SetRow: Identifiable, Equatable {
        var id = UUID()
        var repsText = ""
        var weightText = ""
        var isWarmup = false
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var draft: StrengthDraft {
        StrengthDraft(
            name: trimmedName,
            sets: sets
                .filter { NumberText.value($0.repsText) > 0 }
                .map {
                    SetDraft(
                        reps: Int(NumberText.value($0.repsText)),
                        weightKg: NumberText.value($0.weightText),
                        isWarmup: $0.isWarmup
                    )
                },
            kcalBurned: NumberText.value(kcalText),
            kcalSource: kcalSource
        )
    }

    private var isValid: Bool { !trimmedName.isEmpty && !draft.sets.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledField(label: "动作") {
                ExercisePicker(kind: .strength, name: $name)
            }

            SectionLabel(text: "组")
                .padding(.horizontal, 0)

            VStack(spacing: 0) {
                ForEach($sets) { $row in
                    if sets.first?.id != row.id { Divider().padding(.leading, 14) }
                    setRow($row)
                }
            }
            .cardBackground(cornerRadius: 13)
            .padding(.bottom, 10)

            GhostButton(title: "加一组", systemImage: "plus") {
                // 沿用上一组的重量:同一动作各组重量通常一样,省掉重复输入
                let last = sets.last
                sets.append(SetRow(weightText: last?.weightText ?? "", isWarmup: false))
            }
            .padding(.bottom, 14)

            if draft.volumeKg > 0 {
                summaryRow
            }

            HStack(spacing: 10) {
                LabeledField(label: "消耗") { DecimalField(placeholder: "0", text: $kcalText, unit: "kcal") }
                LabeledField(label: "消耗来源") {
                    Picker("", selection: $kcalSource) {
                        ForEach(KcalSource.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if kcalSource == .device && NumberText.value(kcalText) > 0 {
                Text("设备读数误差可达 ±25%,导出分析时会一并标注,不作为精确值参与能量平衡。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
                    .lineSpacing(3)
                    .padding(.bottom, 14)
            }

            VStack(spacing: 9) {
                PrimaryButton(title: initial == nil ? "记录" : "保存", enabled: isValid) {
                    onSubmit(draft)
                }
                if let onDelete {
                    GhostButton(title: "删除", systemImage: "trash", destructive: true, action: onDelete)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private func setRow(_ row: Binding<SetRow>) -> some View {
        HStack(spacing: 8) {
            DecimalField(placeholder: String(localized: "次数"), text: row.repsText)
                .frame(maxWidth: .infinity)
            DecimalField(placeholder: String(localized: "重量"), text: row.weightText, unit: "kg")
                .frame(maxWidth: .infinity)
            Button {
                row.wrappedValue.isWarmup.toggle()
            } label: {
                Image(systemName: row.wrappedValue.isWarmup ? "flame.fill" : "flame")
                    .font(.system(size: 14))
                    .frame(width: 36, height: 36)
                    .background(
                        row.wrappedValue.isWarmup ? Color("BrandGreen").opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(row.wrappedValue.isWarmup ? Color("BrandGreen") : Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "标记为热身组"))
            Button {
                sets.removeAll { $0.id == row.wrappedValue.id }
                if sets.isEmpty { sets = [SetRow()] }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .frame(width: 30, height: 36)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "删除这一组"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var summaryRow: some View {
        HStack {
            Text("容量 \(Int(draft.volumeKg)) kg")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color("TextPrimary"))
            Spacer()
            if draft.bestE1RM > 0 {
                Text("估算 1RM \(Int(draft.bestE1RM)) kg")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .cardBackground(cornerRadius: 13)
        .padding(.bottom, 14)
    }

    private func prefill() {
        guard !didPrefill, let initial else { didPrefill = true; return }
        didPrefill = true
        name = initial.name
        kcalText = NumberText.text(initial.kcalBurned)
        kcalSource = initial.kcalSource
        sets = initial.sets.map {
            SetRow(
                repsText: $0.reps > 0 ? String($0.reps) : "",
                weightText: NumberText.text($0.weightKg),
                isWarmup: $0.isWarmup
            )
        }
        if sets.isEmpty { sets = [SetRow()] }
    }
}
