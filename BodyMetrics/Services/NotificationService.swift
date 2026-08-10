import Foundation
import UserNotifications

/// 每日 08:00 本地提醒(开关控制,权限被拒时由调用方引导)
enum NotificationService {
    static let reminderIdentifier = "daily-weight-reminder"
    static let reminderHour = 8
    static let reminderMinute = 0

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 注册每天 08:00 重复提醒(先清掉旧的同名请求)
    static func scheduleDailyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "该记录体重啦")
        content.body = ""

        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}
