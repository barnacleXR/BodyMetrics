import Foundation
import SwiftData

/// 一份 AI 分析存档。
///
/// 连同当时导出的数据快照一起存,否则几周后回看结论时无从判断它基于什么数据得出。
@Model
final class AIReport {
    var createdAt: Date = Date.now
    var rangeFrom: Date = Date.now
    var rangeTo: Date = Date.now
    var promptUsed: String = ""
    var responseText: String = ""
    /// 导出时的完整 JSON payload
    var payloadSnapshot: Data = Data()

    init(
        createdAt: Date = .now,
        rangeFrom: Date,
        rangeTo: Date,
        promptUsed: String,
        responseText: String,
        payloadSnapshot: Data
    ) {
        self.createdAt = createdAt
        self.rangeFrom = rangeFrom
        self.rangeTo = rangeTo
        self.promptUsed = promptUsed
        self.responseText = responseText
        self.payloadSnapshot = payloadSnapshot
    }
}
