import SwiftUI
import SwiftData

/// 常用食物库。记录过的食物自动入库,这里用来改错值或清理
struct FoodLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var presets: [FoodPreset]

    enum SortOrder: String, CaseIterable, Hashable {
        case used, recent, name

        var label: String {
            switch self {
            case .used: return String(localized: "最常用")
            case .recent: return String(localized: "最近用")
            case .name: return String(localized: "名称")
            }
        }
    }

    @State private var query = ""
    @State private var sort: SortOrder = .used
    @State private var editing: FoodPreset?
    @State private var creatingNew = false

    private var filtered: [FoodPreset] {
        let keyword = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = keyword.isEmpty ? presets : presets.filter { $0.name.lowercased().contains(keyword) }
        switch sort {
        case .used:
            list.sort { $0.usageCount > $1.usageCount }
        case .recent:
            list.sort { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "常用食物") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlainField(placeholder: String(localized: "搜索"), text: $query)
                        .padding(.bottom, 12)

                    Picker("", selection: $sort) {
                        ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 14)

                    GhostButton(title: "新增食物", systemImage: "plus") { creatingNew = true }
                        .padding(.bottom, 14)

                    if filtered.isEmpty {
                        EmptyHint(text: query.isEmpty
                                  ? "记录过的食物会自动出现在这里。"
                                  : "没有匹配的食物。")
                            .cardBackground()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.persistentModelID) { index, preset in
                                if index > 0 { Divider().padding(.leading, 14) }
                                row(preset)
                            }
                        }
                        .cardBackground()
                    }
                }
                .padding(.horizontal, 23)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(item: $editing) { preset in
            FoodPresetEditor(preset: preset)
        }
        .sheet(isPresented: $creatingNew) {
            FoodPresetEditor(preset: nil)
        }
    }

    private func row(_ preset: FoodPreset) -> some View {
        Button {
            editing = preset
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Color("TextPrimary"))
                        .lineLimit(1)
                    Text(preset.summaryText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineLimit(1)
                }
                Spacer()
                Text(String(localized: "\(preset.usageCount) 次"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 新增/编辑一条常用食物
private struct FoodPresetEditor: View {
    let preset: FoodPreset?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var basis: FoodBasis = .per100g
    @State private var servingLabel = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbText = ""
    @State private var showDeleteConfirm = false
    @State private var didPrefill = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: preset == nil ? "新增食物" : "编辑食物") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LabeledField(label: "名称") {
                        PlainField(placeholder: String(localized: "鸡胸肉"), text: $name)
                    }
                    LabeledField(label: "营养基准") {
                        Picker("", selection: $basis) {
                            ForEach(FoodBasis.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if basis == .perServing {
                        LabeledField(label: "一份的说法") {
                            PlainField(placeholder: String(localized: "个 / 碗 / 盒"), text: $servingLabel)
                        }
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "热量") { DecimalField(placeholder: "165", text: $kcalText, unit: "kcal") }
                        LabeledField(label: "蛋白质") { DecimalField(placeholder: "31", text: $proteinText, unit: "g") }
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "脂肪") { DecimalField(placeholder: "3.6", text: $fatText, unit: "g") }
                        LabeledField(label: "碳水") { DecimalField(placeholder: "0", text: $carbText, unit: "g") }
                    }

                    Text("改这里只影响以后录入时带出的默认值。已经记过的内容存的是当时的数值,不会被追溯修改。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineSpacing(3)
                        .padding(.bottom, 16)

                    VStack(spacing: 9) {
                        PrimaryButton(title: "保存", enabled: isValid, action: save)
                        if preset != nil {
                            GhostButton(title: "删除", systemImage: "trash", destructive: true) {
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 23)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear(perform: prefill)
        .confirmationDialog(
            Text("从库里删除「\(name)」?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "删除"), role: .destructive) {
                if let preset {
                    context.delete(preset)
                    try? context.save()
                }
                dismiss()
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text("历史记录不受影响。")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preset {
            preset.name = trimmed
            preset.basis = basis
            preset.servingLabel = servingLabel
            preset.kcal = NumberText.value(kcalText)
            preset.proteinG = NumberText.value(proteinText)
            preset.fatG = NumberText.value(fatText)
            preset.carbG = NumberText.value(carbText)
        } else {
            context.insert(FoodPreset(
                name: trimmed, basis: basis, servingLabel: servingLabel,
                kcal: NumberText.value(kcalText), proteinG: NumberText.value(proteinText),
                fatG: NumberText.value(fatText), carbG: NumberText.value(carbText)
            ))
        }
        try? context.save()
        dismiss()
    }

    private func prefill() {
        guard !didPrefill, let preset else { didPrefill = true; return }
        didPrefill = true
        name = preset.name
        basis = preset.basis
        servingLabel = preset.servingLabel
        kcalText = NumberText.text(preset.kcal)
        proteinText = NumberText.text(preset.proteinG)
        fatText = NumberText.text(preset.fatG)
        carbText = NumberText.text(preset.carbG)
    }
}
