import SwiftUI

/// 表单里的一个字段:小标题 + 内容,右侧可挂一个链接按钮
struct LabeledField<Content: View>: View {
    let label: LocalizedStringKey
    var action: (() -> AnyView)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
                if let action { action() }
            }
            content
        }
        .padding(.bottom, 14)
    }
}

/// 数字输入框。用 decimalPad 而不是 numberPad:份量与重量都可能是小数
struct DecimalField: View {
    var placeholder: String = ""
    @Binding var text: String
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 15, design: .monospaced))
                .monospacedDigit()
                .onChange(of: text) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber || $0 == "." }
                    if filtered != newValue { text = filtered }
                }
            if let unit {
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Color("CardBackground"))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color("TextSecondary").opacity(0.25), lineWidth: 1)
            )
    }
}

/// 普通文本输入框,与 DecimalField 同款外观
struct PlainField: View {
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 15))
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color("CardBackground"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Color("TextSecondary").opacity(0.25), lineWidth: 1)
                    )
            )
    }
}

/// 主按钮
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .background(enabled ? Color("BrandGreen") : Color.secondary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 15))
            .foregroundStyle(.white)
        }
        .disabled(!enabled)
    }
}

/// 次级按钮(卡片底色)
struct GhostButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
                }
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                destructive ? Color.red.opacity(0.12) : Color("CardBackground"),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : Color("TextPrimary"))
        }
    }
}

/// 弹层标题栏(抓手 + 标题 + 关闭)
struct SheetHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

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
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color("PageBackground")).frame(width: 30, height: 30))
                        .foregroundStyle(Color("TextSecondary"))
                }
                .accessibilityLabel(String(localized: "关闭"))
            }
            .padding(.horizontal, 23)
            .padding(.top, 14)
        }
    }
}

/// 分组小标题
struct SectionLabel: View {
    let text: LocalizedStringKey
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 7)
    }
}

/// 空态文案
struct EmptyHint: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color("TextSecondary"))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .padding(.horizontal, 12)
    }
}

extension View {
    /// 卡片底:与现有页面的圆角卡统一
    func cardBackground(cornerRadius: CGFloat = 17) -> some View {
        background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 数字文本 ↔ Double 的转换。空串视为 0,不把 "" 当成非法输入拦下来
enum NumberText {
    static func value(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    static func text(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return value == value.rounded()
            ? String(Int(value))
            : StatsCalculator.format1(value)
    }
}
