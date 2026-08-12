import SwiftUI
import SwiftData

/// 动作选择:可直接打字新建,也可从内置库与自定义库里挑。
/// 打了新名字直接记录也不会丢——保存时会自动进自定义库(见 DayLogService.ensureCustomExercise)
struct ExercisePicker: View {
    let kind: ExerciseKind
    @Binding var name: String

    @Query private var customExercises: [CustomExercise]
    @Query private var profiles: [UserProfile]

    @State private var showPicker = false

    private var hiddenIDs: [String] { profiles.first?.hiddenBuiltinExerciseIDs ?? [] }

    private var options: [ExerciseCatalog.Entry] {
        let custom = customExercises
            .filter { $0.kind == kind }
            .map { ExerciseCatalog.Entry(id: $0.persistentModelID.hashValue.description, name: $0.name, group: $0.group) }
        let builtin = ExerciseCatalog.builtin(for: kind).filter { !hiddenIDs.contains($0.id) }
        return custom + builtin
    }

    var body: some View {
        HStack(spacing: 8) {
            PlainField(placeholder: kind == .cardio ? String(localized: "跑步机") : String(localized: "卧推"), text: $name)
            Button {
                showPicker = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 40)
                    .background(Color("BrandGreen").opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(Color("BrandGreen"))
            }
            .accessibilityLabel(String(localized: "从动作库选择"))
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet(kind: kind, options: options) { picked in
                name = picked
                showPicker = false
            }
        }
    }
}

private struct ExercisePickerSheet: View {
    let kind: ExerciseKind
    let options: [ExerciseCatalog.Entry]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var grouped: [(group: String, entries: [ExerciseCatalog.Entry])] {
        let keyword = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = keyword.isEmpty ? options : options.filter { $0.name.lowercased().contains(keyword) }
        let dict = Dictionary(grouping: filtered, by: \.group)
        let order = ExerciseCatalog.strengthGroupOrder
        return dict.keys.sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs) ?? Int.max
            let r = order.firstIndex(of: rhs) ?? Int.max
            return l == r ? lhs < rhs : l < r
        }.map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "动作库") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlainField(placeholder: String(localized: "搜索"), text: $query)
                        .padding(.bottom, 16)

                    if grouped.isEmpty {
                        EmptyHint(text: "没有匹配的动作。直接在上一页输入名称即可新建。")
                    }

                    ForEach(grouped, id: \.group) { section in
                        SectionLabel(text: LocalizedStringKey(section.group))
                            .padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 14) }
                                Button {
                                    onPick(entry.name)
                                } label: {
                                    HStack {
                                        Text(entry.name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color("TextPrimary"))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 46)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .cardBackground()
                        .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 23)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}
