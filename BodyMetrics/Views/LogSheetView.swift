import SwiftUI
import SwiftData

/// 记录弹层:指标切换 + 原生 decimalPad 键盘 + 追加保存
struct LogSheetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 初始指标(默认体重);targetDate 非 nil 时为日历页编辑(保存到该日)
    var initialMetric: Metric = .weight
    var targetDate: Date? = nil
    var initialValue: String? = nil

    @State private var metricSelection: Metric
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(initialMetric: Metric = .weight, targetDate: Date? = nil, initialValue: String? = nil) {
        self.initialMetric = initialMetric
        self.targetDate = targetDate
        self.initialValue = initialValue
        _metricSelection = State(initialValue: initialMetric)
        _text = State(initialValue: initialValue ?? "")
    }

    private var title: String {
        metricSelection == .weight ? String(localized: "记录体重") : String(localized: "记录体脂率")
    }

    private var hint: String {
        metricSelection == .weight
            ? String(localized: "输入体重,可输入 1 位小数,如 62.4 kg")
            : String(localized: "输入体脂率,可输入 1 位小数,如 18.6 %")
    }

    private var parsedValue: Double? { Double(text) }

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
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                    .font(.system(size: 46, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color("BrandGreen"))
                    .multilineTextAlignment(.center)
                    .onChange(of: text) { _, newValue in
                        text = Self.sanitize(newValue)
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

    /// 追加保存(同日同指标允许多条,不覆盖历史)
    private func save() {
        guard let value = parsedValue else { return }
        let entry = MetricEntry(metric: metricSelection, value: value, date: targetDate ?? .now)
        context.insert(entry)
        try? context.save()
        dismiss()
    }

    /// 输入过滤:仅数字与一个小数点,小数部分最多 1 位,整数位不限
    private static func sanitize(_ input: String) -> String {
        var result = ""
        var hasDot = false
        var fractionDigits = 0
        for ch in input {
            if ch == "." {
                if hasDot { continue }
                hasDot = true
                result.append(ch)
            } else if ch.isNumber {
                if hasDot {
                    fractionDigits += 1
                    if fractionDigits > 1 { continue }
                }
                result.append(ch)
            }
        }
        return result
    }
}

#Preview {
    LogSheetView()
        .modelContainer(for: [MetricEntry.self, UserProfile.self], inMemory: true)
}
