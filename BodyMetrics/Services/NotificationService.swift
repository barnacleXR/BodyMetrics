import Foundation
import UserNotifications

/// 每日本地提醒:时间由用户自定,可设多条;总开关关闭时全部撤销
enum NotificationService {
    /// 所有提醒请求的 identifier 前缀,便于整体清理
    static let reminderIdentifierPrefix = "weight-reminder-"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 用当前提醒列表重建全部通知请求(先清空旧的,避免删改后残留)。
    /// `enabled` 为总开关:关闭时只清空不注册
    static func sync(times: [(id: UUID, hour: Int, minute: Int, kind: ReminderKind)], enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        await cancelAll(center: center)
        guard enabled else { return }

        for time in times {
            let content = UNMutableNotificationContent()
            // 文案跟着提醒类型走:晚上七点弹"该记录体重啦"没道理
            content.title = title(for: time.kind)
            content.body = time.kind.notificationBody
            content.sound = .default

            var components = DateComponents()
            components.hour = time.hour
            components.minute = time.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: reminderIdentifierPrefix + time.id.uuidString,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private static func title(for kind: ReminderKind) -> String {
        switch kind {
        case .weighIn: return String(localized: "该称体重啦")
        case .meal: return String(localized: "别忘了记这一餐")
        case .postWorkout: return String(localized: "训练完了吗")
        }
    }

    static func cancelAll() async {
        await cancelAll(center: UNUserNotificationCenter.current())
    }

    private static func cancelAll(center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(reminderIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
