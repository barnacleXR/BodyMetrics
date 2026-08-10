import SwiftUI
import SwiftData

@main
struct BodyMetricsApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: MetricEntry.self, UserProfile.self)
        ensureUserProfile(in: container.mainContext)
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
}
