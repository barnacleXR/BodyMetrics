import SwiftUI
import SwiftData

/// 主框架:4 tab 底部导航(iOS 26 原生 Liquid Glass TabView,不自定义)
struct RootTabView: View {
    enum AppTab: Hashable {
        case record, calendar, trend, settings
    }

    @State private var selection: AppTab = .record
    @Query private var profiles: [UserProfile]
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = false
    @State private var pendingUnlock = false

    private var lockEnabled: Bool { profiles.first?.biometricLockEnabled ?? false }

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                Tab("记录", systemImage: "pencil", value: AppTab.record) {
                    RecordView(selection: $selection)
                }
                Tab("日历", systemImage: "calendar", value: AppTab.calendar) {
                    CalendarView()
                }
                Tab("趋势", systemImage: "chart.xyaxis.line", value: AppTab.trend) {
                    TrendView()
                }
                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tint(Color("BrandGreen"))

            if isLocked {
                LockView {
                    Task { await unlock() }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                if lockEnabled { isLocked = true }
            } else if phase == .active {
                if isLocked && lockEnabled {
                    pendingUnlock = true
                }
            }
        }
        .onChange(of: pendingUnlock) { _, value in
            if value {
                Task { await unlock() }
            }
        }
    }

    /// 进后台即锁定;回前台时验证,通过才解锁
    private func unlock() async {
        let reason = String(localized: "用于解锁你的体重记录")
        let ok = await BiometricLockService.authenticate(reason: reason)
        if ok {
            isLocked = false
        }
        pendingUnlock = false
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [MetricEntry.self, UserProfile.self], inMemory: true)
}
