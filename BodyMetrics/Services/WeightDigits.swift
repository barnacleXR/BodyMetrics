import Foundation

/// 体重/体脂率输入框的"自动小数点"规则。
///
/// 用户只按数字键,小数点由这里插入:满 2 位显式补出小数点(62 → "62."),
/// 第 3 位起最后一位作为小数位(624 → "62.4"、1004 → "100.4"),小数部分恒为 1 位。
/// 提出来是为了让记录弹层与记录页的快速录入用同一套规则,不各写一份。
enum WeightDigits {
    /// 数字串上限 4 位,即最大 999.9;整数位不限制在 3 位以内(可记 100 kg 以上)
    static let maxDigits = 4

    /// 只保留 0–9 并截断到上限。小数点由 `display(for:)` 自动插入,故忽略用户键入的小数点
    static func onlyDigits(_ input: String) -> String {
        String(input.filter { $0 >= "0" && $0 <= "9" }.prefix(maxDigits))
    }

    /// 数字串 → 显示值
    static func display(for digits: String) -> String {
        switch digits.count {
        case 0, 1: return digits
        case 2: return digits + "."
        default: return "\(digits.dropLast()).\(digits.suffix(1))"
        }
    }

    /// 已格式化的值(如 "62.4")→ 数字串;带小数且不足 3 位时左补 0,
    /// 保证回显与该值一致(8.5 → "085" → "08.5",而非 "85" → 85)
    static func digits(fromFormatted value: String) -> String {
        let digits = onlyDigits(value)
        guard value.contains("."), digits.count < 3 else { return digits }
        return String(repeating: "0", count: 3 - digits.count) + digits
    }

    /// 由显示文本解析出数值。与 `display(for:)` 同一套规则,不依赖尾随小数点的写法。0 是合法值
    static func value(fromDisplay text: String) -> Double? {
        let digits = onlyDigits(text)
        guard !digits.isEmpty else { return nil }
        guard digits.count > 2 else { return Double(digits) }
        return Double("\(digits.dropLast()).\(digits.suffix(1))")
    }

    /// 处理一次编辑。退格删掉的是自动补出的小数点时按删掉前一位数字处理,
    /// 否则小数点会被立刻补回来,"62." 永远退不回 "6"
    static func reformat(oldValue: String, newValue: String) -> String {
        var digits = onlyDigits(newValue)
        if oldValue.hasSuffix("."), newValue == String(oldValue.dropLast()) {
            digits = String(digits.dropLast())
        }
        return display(for: digits)
    }
}
