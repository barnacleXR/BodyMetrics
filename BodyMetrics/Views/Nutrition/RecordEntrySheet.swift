import SwiftUI
import SwiftData

/// 统一的录入弹层:体重 / 饮食 / 力量 / 有氧 四选一。
///
/// 四个领域共用一个入口,是"记录页 = 这一天的全部"这条融合原则在交互上的落点——
/// 用户不需要先想清楚"这属于哪个模块"再决定点哪个按钮。
struct RecordEntrySheet: View {
    enum Mode: String, CaseIterable, Hashable {
        case weight, food, strength, cardio

        var label: String {
            switch self {
            case .weight: return String(localized: "体重")
            case .food: return String(localized: "饮食")
            case .strength: return String(localized: "力量")
            case .cardio: return String(localized: "有氧")
            }
        }
    }

    /// 记录到哪一天(补录时非今天)
    let date: Date
    var initialMode: Mode = .food
    var onRecorded: (String) -> Void
    /// 加入试算(不落盘)。由记录页持有试算内容,所以这里只往上抛
    var onAddToDraft: ((FoodDraft, MealType) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]

    @State private var mode: Mode = .food
    @State private var didSetMode = false
    @State private var showFoodLibrary = false
    @State private var showExerciseLibrary = false

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title) { dismiss() }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 23)
            .padding(.top, 14)

            HStack {
                if !isToday {
                    Text("补录到 \(date.formatted(.dateTime.month().day()))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer()
                if mode != .weight {
                    Button(mode == .food ? String(localized: "常用食物") : String(localized: "动作库")) {
                        if mode == .food { showFoodLibrary = true } else { showExerciseLibrary = true }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color("BrandGreen"))
                }
            }
            .frame(minHeight: 18)
            .padding(.horizontal, 23)
            .padding(.top, 10)

            ScrollView {
                Group {
                    switch mode {
                    case .weight:
                        WeightEntryForm(date: date) { message in
                            onRecorded(message)
                            dismiss()
                        }
                    case .food:
                        FoodFormView(
                            initial: nil,
                            onSubmit: { draft, mealType in
                                DayLogService.addFood(draft, mealType: mealType, on: date, in: context)
                                onRecorded(String(localized: "已记录"))
                                dismiss()
                            },
                            onAddToDraft: onAddToDraft.map { handler in
                                { draft, mealType in
                                    handler(draft, mealType)
                                    dismiss()
                                }
                            }
                        )
                    case .strength:
                        StrengthFormView(initial: nil) { draft in
                            DayLogService.addStrength(draft, on: date, in: context)
                            onRecorded(String(localized: "已记录"))
                            dismiss()
                        }
                    case .cardio:
                        CardioFormView(initial: nil) { draft in
                            DayLogService.addCardio(draft, on: date, in: context)
                            onRecorded(String(localized: "已记录"))
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 23)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showFoodLibrary) { FoodLibraryView() }
        .sheet(isPresented: $showExerciseLibrary) {
            ExerciseLibraryView(initialKind: mode == .cardio ? .cardio : .strength)
        }
        .onAppear {
            guard !didSetMode else { return }
            didSetMode = true
            mode = initialMode
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .weight: return "记录体重"
        case .food: return "记录饮食"
        case .strength: return "记录力量训练"
        case .cardio: return "记录有氧"
        }
    }
}

/// 记录页内嵌的体重录入。与记录弹层共用 `WeightDigits` 的自动小数点规则
private struct WeightEntryForm: View {
    let date: Date
    let onSaved: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]

    @State private var metric: Metric = .weight
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Double? { WeightDigits.value(fromDisplay: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $metric) {
                Text("体重").tag(Metric.weight)
                Text("体脂率").tag(Metric.bodyFat)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 12)
            .onChange(of: metric) { _, _ in text = "" }

            Text(metric == .weight
                 ? "输入体重,第 2 位数字后自动出现小数点,如输入 624 → 62.4 kg"
                 : "输入体脂率,第 2 位数字后自动出现小数点,如输入 186 → 18.6 %")
                .font(.system(size: 12))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.bottom, 18)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(.system(size: 46, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color("BrandGreen"))
                    .multilineTextAlignment(.center)
                    .onChange(of: text) { oldValue, newValue in
                        let formatted = WeightDigits.reformat(oldValue: oldValue, newValue: newValue)
                        if formatted != newValue { text = formatted }
                    }
                Text(metric.unit)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("TextSecondary"))
            }
            .padding(.bottom, 22)

            PrimaryButton(title: "完成", enabled: parsed != nil, action: save)
        }
        .onAppear { focused = true }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "收起键盘")) { focused = false }
            }
        }
    }

    /// 追加写入,不覆盖历史。补录到过去某天时时间戳排在当日最新一条之后,保证成为当日代表值
    private func save() {
        guard let value = parsed else { return }
        let calendar = Calendar.current
        var timestamp = date
        if !calendar.isDateInToday(date) {
            let dayStart = calendar.startOfDay(for: date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
            let latestSameDay = entries
                .filter { $0.metric == metric && $0.date >= dayStart && $0.date < dayEnd }
                .max { $0.date < $1.date }
            timestamp = latestSameDay.map {
                min($0.date.addingTimeInterval(1), dayEnd.addingTimeInterval(-1))
            } ?? calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart
        } else {
            timestamp = .now
        }
        context.insert(MetricEntry(metric: metric, value: value, date: timestamp))
        try? context.save()
        onSaved(String(localized: "已记录"))
    }
}
