import SwiftUI
import SwiftData

/// 动作库管理:力量/有氧切换、搜索、新增自定义、隐藏内置、重命名(同步改写历史)
struct ExerciseLibraryView: View {
    var initialKind: ExerciseKind = .strength

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var customExercises: [CustomExercise]
    @Query private var profiles: [UserProfile]

    @State private var kind: ExerciseKind = .strength
    @State private var query = ""
    @State private var newName = ""
    @State private var renaming: RenameTarget?
    @State private var didSetKind = false
    @State private var toastMessage: ToastMessage?

    private struct RenameTarget: Identifiable {
        let id = UUID()
        let oldName: String
        let kind: ExerciseKind
    }

    private var profile: UserProfile? { profiles.first }
    private var hiddenIDs: [String] { profile?.hiddenBuiltinExerciseIDs ?? [] }
    private var customs: [CustomExercise] { customExercises.filter { $0.kind == kind } }

    private func matches(_ name: String) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespaces).lowercased()
        return keyword.isEmpty || name.lowercased().contains(keyword)
    }

    private var groupedBuiltins: [(group: String, entries: [ExerciseCatalog.Entry])] {
        let dict = Dictionary(grouping: ExerciseCatalog.builtin(for: kind).filter { matches($0.name) }, by: \.group)
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
                    Picker("", selection: $kind) {
                        ForEach(ExerciseKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 12)

                    PlainField(placeholder: String(localized: "搜索"), text: $query)
                        .padding(.bottom, 14)

                    HStack(spacing: 8) {
                        PlainField(placeholder: String(localized: "新增自定义动作"), text: $newName)
                        Button(String(localized: "添加")) { addCustom() }
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 66, height: 40)
                            .background(
                                newName.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.secondary.opacity(0.3) : Color("BrandGreen"),
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                            .foregroundStyle(.white)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.bottom, 20)

                    if !customs.isEmpty {
                        customSection
                    }
                    builtinSections
                }
                .padding(.horizontal, 23)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .toast($toastMessage)
        .sheet(item: $renaming) { target in
            RenameExerciseSheet(oldName: target.oldName, kind: target.kind) { touched in
                toastMessage = ToastMessage(
                    text: touched > 0
                        ? String(localized: "已改名,同步更新 \(touched) 条历史记录")
                        : String(localized: "已改名")
                )
            }
        }
        .onAppear {
            guard !didSetKind else { return }
            didSetKind = true
            kind = initialKind
        }
    }

    // MARK: - 自定义

    private var customSection: some View {
        let visible = customs.filter { matches($0.name) }
        return VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "自定义")
            VStack(spacing: 0) {
                if visible.isEmpty {
                    EmptyHint(text: "没有匹配的自定义动作。")
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.persistentModelID) { index, exercise in
                        if index > 0 { Divider().padding(.leading, 14) }
                        customRow(exercise)
                    }
                }
            }
            .cardBackground()
            .padding(.bottom, 16)
        }
    }

    private func customRow(_ exercise: CustomExercise) -> some View {
        HStack(spacing: 8) {
            Text(exercise.name)
                .font(.system(size: 14))
                .foregroundStyle(Color("TextPrimary"))
            Spacer()
            Button {
                renaming = RenameTarget(oldName: exercise.name, kind: kind)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "重命名 \(exercise.name)"))
            Button {
                ExerciseLibraryService.deleteCustom(exercise, in: context)
                toastMessage = ToastMessage(text: String(localized: "已从库中删除,历史记录不受影响"))
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "删除 \(exercise.name)"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 50)
    }

    // MARK: - 内置

    private var builtinSections: some View {
        ForEach(groupedBuiltins, id: \.group) { section in
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(text: LocalizedStringKey(section.group))
                VStack(spacing: 0) {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.leading, 14) }
                        builtinRow(entry)
                    }
                }
                .cardBackground()
                .padding(.bottom, 12)
            }
        }
    }

    private func builtinRow(_ entry: ExerciseCatalog.Entry) -> some View {
        let hidden = hiddenIDs.contains(entry.id)
        return HStack(spacing: 8) {
            Text(entry.name)
                .font(.system(size: 14))
                .foregroundStyle(hidden ? Color("TextSecondary") : Color("TextPrimary"))
                .strikethrough(hidden, color: Color("TextSecondary"))
            Spacer()
            Button {
                renaming = RenameTarget(oldName: entry.name, kind: kind)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "重命名 \(entry.name)"))
            Button {
                guard let profile else { return }
                ExerciseLibraryService.toggleHidden(builtinID: entry.id, profile: profile, in: context)
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(hidden ? Color("BrandGreen") : Color("TextSecondary"))
            }
            .accessibilityLabel(hidden
                                ? String(localized: "取消隐藏 \(entry.name)")
                                : String(localized: "隐藏 \(entry.name)"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 50)
    }

    private func addCustom() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DayLogService.ensureCustomExercise(named: trimmed, kind: kind, in: context)
        try? context.save()
        newName = ""
    }
}

/// 重命名弹层。文案要说清历史会一起改,否则用户不敢点
private struct RenameExerciseSheet: View {
    let oldName: String
    let kind: ExerciseKind
    let onRenamed: (Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var didPrefill = false

    private var isValid: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != oldName
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "重命名动作") { dismiss() }
            VStack(alignment: .leading, spacing: 0) {
                LabeledField(label: "名称") {
                    PlainField(text: $newName)
                }
                Text("历史记录里的这个动作会一起改名,否则统计里会裂成两个动作。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
                    .lineSpacing(3)
                    .padding(.bottom, 16)
                PrimaryButton(title: "保存", enabled: isValid) {
                    let modelContext = context
                    let touched = ExerciseLibraryService.rename(
                        from: oldName, to: newName, kind: kind, in: modelContext
                    )
                    dismiss()
                    onRenamed(touched)
                }
                Spacer()
            }
            .padding(.horizontal, 23)
            .padding(.top, 16)
        }
        .background(Color("PageBackground"))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            newName = oldName
        }
    }
}
