import SwiftUI
import SwiftData

@main
struct BodyMetricsApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: MetricEntry.self, UserProfile.self, Reminder.self)
        ensureUserProfile(in: container.mainContext)
        ensureDefaultReminder(in: container.mainContext)
        syncReminders(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }

    /// 启动时确保存在唯一的 UserProfile(默认值:目标 58.0 kg、身高 170 cm、提醒开、生物识别锁关)
    private func ensureUserProfile(in context: ModelContext) {
        let descriptor = FetchDescriptor<UserProfile>()
        guard (try? context.fetchCount(descriptor)) ?? 0 == 0 else { return }
        context.insert(UserProfile())
        try? context.save()
    }

    /// 首次启动种一条 08:00 提醒(沿用旧版默认);用户删光后不再自动补,尊重"一条都不要"
    private func ensureDefaultReminder(in context: ModelContext) {
        let hasSeeded = UserDefaults.standard.bool(forKey: "didSeedDefaultReminder")
        guard !hasSeeded else { return }
        UserDefaults.standard.set(true, forKey: "didSeedDefaultReminder")
        let descriptor = FetchDescriptor<Reminder>()
        guard (try? context.fetchCount(descriptor)) ?? 0 == 0 else { return }
        context.insert(Reminder(hour: 8, minute: 0))
        try? context.save()
    }

    /// 启动时按当前提醒列表与总开关重建通知请求(时区变更、系统清理后也能自愈)
    private func syncReminders(in context: ModelContext) {
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let enabled = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.reminderEnabled ?? true
        let times = reminders
            .sorted { $0.minutesOfDay < $1.minutesOfDay }
            .map { (id: $0.id, hour: $0.hour, minute: $0.minute) }
        Task { await NotificationService.sync(times: times, enabled: enabled) }
    }
}
