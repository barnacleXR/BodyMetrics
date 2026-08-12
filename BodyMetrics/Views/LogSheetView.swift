import SwiftUI
import SwiftData

/// 记录弹层:指标切换 + 原生 numberPad 键盘(小数点自动插入)+ 追加保存
struct LogSheetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]

    /// 初始指标(默认体重);targetDate 非 nil 时为日历页编辑(保存到该日)
    var initialMetric: Metric = .weight
    var targetDate: Date? = nil
    var initialValue: String? = nil

    @State private var metricSelection: Metric
    /// 输入框文本,始终是 `display(for:)` 的结果(小数点自动插入,不由用户键入)
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(initialMetric: Metric = .weight, targetDate: Date? = nil, initialValue: String? = nil) {
        self.initialMetric = initialMetric
        self.targetDate = targetDate
        self.initialValue = initialValue
        _metricSelection = State(initialValue: initialMetric)
        _text = State(initialValue: WeightDigits.display(for: WeightDigits.digits(fromFormatted: initialValue ?? "")))
    }

    private var title: String {
        metricSelection == .weight ? String(localized: "记录体重") : String(localized: "记录体脂率")
    }

    private var hint: String {
        metricSelection == .weight
            ? String(localized: "输入体重,第 2 位数字后自动出现小数点,如输入 624 → 62.4 kg")
            : String(localized: "输入体脂率,第 2 位数字后自动出现小数点,如输入 186 → 18.6 %")
    }

    private var parsedValue: Double? { WeightDigits.value(fromDisplay: text) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 37, height: 5)
                .padding(.top, 12)

            HStack {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.5)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color("PageBackground"))
                                .frame(width: 30, height: 30)
                        )
                        .foregroundStyle(Color("TextSecondary"))
                }
                .accessibilityLabel(String(localized: "关闭"))
            }
            .padding(.horizontal, 23)
            .padding(.top, 20)

            Picker("", selection: $metricSelection) {
                Text("体重").tag(Metric.weight)
                Text("体脂率").tag(Metric.bodyFat)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 23)
            .padding(.top, 14)
            .onChange(of: metricSelection) { _, _ in
                text = ""
            }

            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(Color("TextSecondary"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 23)
                .padding(.top, 10)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .focused($fieldFocused)
                    .font(.system(size: 46, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color("BrandGreen"))
                    .multilineTextAlignment(.center)
                    .onChange(of: text) { oldValue, newValue in
                        // 每次编辑后按数字串重新格式化(小数点位置随位数自动移动)
                        let formatted = WeightDigits.reformat(oldValue: oldValue, newValue: newValue)
                        if formatted != newValue { text = formatted }
                    }
                Text(metricSelection.unit)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("TextSecondary"))
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)

            Button {
                save()
            } label: {
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(parsedValue == nil ? Color.secondary.opacity(0.35) : Color("BrandGreen"), in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.white)
            }
            .disabled(parsedValue == nil)
            .padding(.horizontal, 23)
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .background(Color(.systemBackground))
        .onAppear { fieldFocused = true }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "收起键盘")) { fieldFocused = false }
            }
        }
    }

    /// 追加保存(同日同指标允许多条,不覆盖历史);日历编辑时时间戳置于当日最新之后,保证编辑值成为当日代表值
    private func save() {
        guard let value = parsedValue else { return }
        var date = targetDate ?? .now
        if let targetDate {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: targetDate)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
            let latestSameDay = entries
                .filter { $0.metric == metricSelection && $0.date >= dayStart && $0.date < dayEnd }
                .max { $0.date < $1.date }
            if let latestSameDay {
                // 当日已有记录:排在最新一条之后(不超过当日 23:59:59,避免跨天)
                date = min(latestSameDay.date.addingTimeInterval(1), dayEnd.addingTimeInterval(-1))
            }
        }
        let entry = MetricEntry(metric: metricSelection, value: value, date: date)
        context.insert(entry)
        try? context.save()
        dismiss()
    }

}

#Preview {
    LogSheetView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
