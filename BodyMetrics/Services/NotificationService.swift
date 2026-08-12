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
    static func sync(times: [(id: UUID, hour: Int, minute: Int)], enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        await cancelAll(center: center)
        guard enabled else { return }

        for time in times {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "该记录体重啦")
            content.body = ""
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
