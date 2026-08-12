import SwiftUI
import SwiftData

/// 饮食录入表单。新增与编辑共用
struct FoodFormView: View {
    @Query(sort: \FoodPreset.usageCount, order: .reverse) private var presets: [FoodPreset]

    /// 编辑时传入原值
    var initial: (draft: FoodDraft, mealType: MealType)?
    var onSubmit: (FoodDraft, MealType) -> Void
    /// 加入试算(仅新增时提供)
    var onAddToDraft: ((FoodDraft, MealType) -> Void)?
    var onDelete: (() -> Void)?

    @State private var mealType: MealType = FoodFormView.defaultMealType()
    @State private var name = ""
    @State private var basis: FoodBasis = .per100g
    @State private var servingLabel = ""
    @State private var amountText = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbText = ""
    @State private var didPrefill = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && NumberText.value(amountText) > 0 }

    private var draft: FoodDraft {
        FoodDraft(
            name: trimmedName, basis: basis,
            servingLabel: servingLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: NumberText.value(amountText),
            kcal: NumberText.value(kcalText),
            proteinG: NumberText.value(proteinText),
            fatG: NumberText.value(fatText),
            carbG: NumberText.value(carbText)
        )
    }

    /// 按当前时间猜一个餐次,省掉最常见的一次点击
    private static func defaultMealType() -> MealType {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }

    /// 名称匹配到的常用食物(最多 5 条)
    private var suggestions: [FoodPreset] {
        guard !trimmedName.isEmpty, initial == nil || !didPrefill else { return [] }
        let keyword = trimmedName.lowercased()
        return presets
            .filter { $0.name.lowercased().contains(keyword) && $0.name != trimmedName }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $mealType) {
                ForEach(MealType.allCases.sorted { $0.order < $1.order }, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 16)

            LabeledField(label: "名称") {
                PlainField(placeholder: String(localized: "鸡胸肉"), text: $name)
            }

            if !suggestions.isEmpty {
                presetSuggestions
            }

            LabeledField(label: "营养基准") {
                Picker("", selection: $basis) {
                    ForEach(FoodBasis.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if basis == .perServing {
                LabeledField(label: "一份的说法") {
                    PlainField(placeholder: String(localized: "个 / 碗 / 盒"), text: $servingLabel)
                }
            }

            LabeledField(label: basis == .per100g ? "份量" : "份数") {
                DecimalField(
                    placeholder: basis == .per100g ? "150" : "1",
                    text: $amountText,
                    unit: basis == .per100g ? "g" : (servingLabel.isEmpty ? String(localized: "份") : servingLabel)
                )
            }

            Text(basis == .per100g ? "下面四项填每 100 g 的值" : "下面四项填每一份的值")
                .font(.system(size: 11))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                LabeledField(label: "热量") { DecimalField(placeholder: "165", text: $kcalText, unit: "kcal") }
                LabeledField(label: "蛋白质") { DecimalField(placeholder: "31", text: $proteinText, unit: "g") }
            }
            HStack(spacing: 10) {
                LabeledField(label: "脂肪") { DecimalField(placeholder: "3.6", text: $fatText, unit: "g") }
                LabeledField(label: "碳水") { DecimalField(placeholder: "0", text: $carbText, unit: "g") }
            }

            if isValid {
                summaryRow
            }

            VStack(spacing: 9) {
                PrimaryButton(title: initial == nil ? "记录" : "保存", enabled: isValid) {
                    onSubmit(draft, mealType)
                }
                if let onAddToDraft {
                    GhostButton(title: "加入试算", systemImage: "cart") {
                        onAddToDraft(draft, mealType)
                    }
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.45)
                }
                if let onDelete {
                    GhostButton(title: "删除", systemImage: "trash", destructive: true, action: onDelete)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private var presetSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, preset in
                if index > 0 { Divider().padding(.leading, 14) }
                Button {
                    apply(preset)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.system(size: 14))
                                .foregroundStyle(Color("TextPrimary"))
                            Text(preset.summaryText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color("TextSecondary"))
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color("BrandGreen"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardBackground(cornerRadius: 13)
        .padding(.bottom, 14)
    }

    private var summaryRow: some View {
        let macros = draft.macros
        return HStack {
            Text("这一条")
                .font(.system(size: 12))
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
            Text("\(Int(macros.kcal.rounded())) kcal · \(macros.summaryText)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color("TextPrimary"))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .cardBackground(cornerRadius: 13)
        .padding(.bottom, 14)
    }

    /// 带出常用食物的营养值(份量保持用户已填的)
    private func apply(_ preset: FoodPreset) {
        name = preset.name
        basis = preset.basis
        servingLabel = preset.servingLabel
        kcalText = NumberText.text(preset.kcal)
        proteinText = NumberText.text(preset.proteinG)
        fatText = NumberText.text(preset.fatG)
        carbText = NumberText.text(preset.carbG)
        if amountText.isEmpty {
            amountText = preset.basis == .per100g ? "100" : "1"
        }
    }

    private func prefill() {
        guard !didPrefill, let initial else { didPrefill = true; return }
        didPrefill = true
        mealType = initial.mealType
        let d = initial.draft
        name = d.name
        basis = d.basis
        servingLabel = d.servingLabel
        amountText = NumberText.text(d.amount)
        kcalText = NumberText.text(d.kcal)
        proteinText = NumberText.text(d.proteinG)
        fatText = NumberText.text(d.fatG)
        carbText = NumberText.text(d.carbG)
    }
}
