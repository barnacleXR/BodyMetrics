import Foundation
import SwiftData

/// 一条每日提醒(可多条,时间用户自定);实际是否发送还受 UserProfile.reminderEnabled 总开关约束
@Model
final class Reminder {
    var id: UUID = UUID()
    var hour: Int = 8
    var minute: Int = 0

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// 排序与去重用的一天内分钟数
    var minutesOfDay: Int { hour * 60 + minute }

    /// 本地化的时间文本(如 "08:00" / "8:00 AM",跟随系统 12/24 小时制)
    var timeText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(.dateTime.hour().minute())
    }
}
