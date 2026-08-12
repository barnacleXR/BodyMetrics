import Testing
@testable import BodyMetrics

/// 自动小数点规则。提取成共享逻辑后由记录弹层与记录页快速录入共用,行为必须保持一致
struct WeightDigitsTests {

    @Test func decimalPointAppearsAfterTwoDigits() {
        #expect(WeightDigits.display(for: "") == "")
        #expect(WeightDigits.display(for: "6") == "6")
        #expect(WeightDigits.display(for: "62") == "62.")
        #expect(WeightDigits.display(for: "624") == "62.4")
        // 整数位不限 3 位,可记 100 kg 以上
        #expect(WeightDigits.display(for: "1004") == "100.4")
    }

    @Test func inputIsCappedAtFourDigits() {
        #expect(WeightDigits.onlyDigits("12345") == "1234")
        #expect(WeightDigits.onlyDigits("6a2.4b") == "624")
    }

    @Test func backspaceOverAutoInsertedDotRemovesADigit() {
        // "62." 退格删掉的是自动补出的小数点,应当退回 "6";否则小数点会被立刻补回来,永远退不动
        #expect(WeightDigits.reformat(oldValue: "62.", newValue: "62") == "6")
        // 正常退格
        #expect(WeightDigits.reformat(oldValue: "62.4", newValue: "62.") == "62.")
    }

    @Test func roundTripPreservesValuesBelowTen() {
        // 8.5 回填必须仍是 8.5,不能变成 85
        let digits = WeightDigits.digits(fromFormatted: "8.5")
        #expect(WeightDigits.display(for: digits) == "08.5")
        #expect(WeightDigits.value(fromDisplay: "08.5") == 8.5)
    }

    @Test func parsingFollowsSameRuleAsDisplay() {
        #expect(WeightDigits.value(fromDisplay: "") == nil)
        #expect(WeightDigits.value(fromDisplay: "6") == 6)
        // 满 2 位时值仍是整数 62,尾随小数点只是显示
        #expect(WeightDigits.value(fromDisplay: "62.") == 62)
        #expect(WeightDigits.value(fromDisplay: "62.4") == 62.4)
        // 0 是合法值
        #expect(WeightDigits.value(fromDisplay: "0") == 0)
    }
}
