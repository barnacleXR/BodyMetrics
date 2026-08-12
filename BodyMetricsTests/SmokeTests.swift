import Testing
@testable import BodyMetrics

/// 测试 target 接线验证:能 import 主模块并调用其中的纯函数
struct SmokeTests {
    @Test func formatsOneDecimal() {
        #expect(StatsCalculator.format1(62.35) == "62.3" || StatsCalculator.format1(62.35) == "62.4")
        #expect(StatsCalculator.format1(8.5) == "8.5")
    }

    @Test func bmiUsesSquareOfHeightInMeters() {
        let value = StatsCalculator.bmi(weightKg: 62, heightCm: 170)
        #expect(abs(value - 21.45) < 0.01)
    }
}
