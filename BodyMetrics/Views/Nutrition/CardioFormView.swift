import SwiftUI

/// 有氧训练录入表单
struct CardioFormView: View {
    var initial: CardioDraft?
    var onSubmit: (CardioDraft) -> Void
    var onDelete: (() -> Void)?

    @State private var name = ""
    @State private var durationText = ""
    @State private var distanceText = ""
    @State private var kcalText = ""
    @State private var kcalSource: KcalSource = .manual
    @State private var didPrefill = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && NumberText.value(durationText) > 0 }

    private var draft: CardioDraft {
        let distance = NumberText.value(distanceText)
        return CardioDraft(
            name: trimmedName,
            durationMin: NumberText.value(durationText),
            distanceKm: distance > 0 ? distance : nil,
            kcalBurned: NumberText.value(kcalText),
            kcalSource: kcalSource
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledField(label: "动作") {
                ExercisePicker(kind: .cardio, name: $name)
            }

            HStack(spacing: 10) {
                LabeledField(label: "时长") { DecimalField(placeholder: "30", text: $durationText, unit: String(localized: "分钟")) }
                LabeledField(label: "距离(可选)") { DecimalField(placeholder: "5", text: $distanceText, unit: "km") }
            }

            HStack(spacing: 10) {
                LabeledField(label: "消耗") { DecimalField(placeholder: "300", text: $kcalText, unit: "kcal") }
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

    private func prefill() {
        guard !didPrefill, let initial else { didPrefill = true; return }
        didPrefill = true
        name = initial.name
        durationText = NumberText.text(initial.durationMin)
        distanceText = initial.distanceKm.map { NumberText.text($0) } ?? ""
        kcalText = NumberText.text(initial.kcalBurned)
        kcalSource = initial.kcalSource
    }
}
