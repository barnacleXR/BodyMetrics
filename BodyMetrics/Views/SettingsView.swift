import SwiftUI
import SwiftData

/// 分享文件包装(URL 需 Identifiable 才能用 sheet(item:))
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 设置页:记录 / 提醒 / 数据与隐私
struct SettingsView: View {
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var profiles: [UserProfile]
    @Query private var reminders: [Reminder]
    @Environment(\.modelContext) private var context

    @State private var showGoalEditor = false
    @State private var goalText = ""
    @State private var showHeightEditor = false
    @State private var heightText = ""
    @State private var showNotificationDeniedAlert = false
    @State private var showReminders = false
    @State private var showBiometricUnavailableAlert = false
    @State private var shareItem: ShareItem? = nil
    @State private var showToast = false
    @State private var toastText = ""

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text("设置")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)

                    // 记录
                    groupTitle("记录")
                    VStack(spacing: 0) {
                        row(icon: "target", iconPale: true, title: "我的目标") {
                            Text(goalValueText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color("TextSecondary"))
                            chevron
                        }
                        .onTapGesture {
                            goalText = profile.map { StatsCalculator.format1($0.goalWeight) } ?? ""
                            showGoalEditor = true
                        }
                        Divider().padding(.leading, 57)
                        row(icon: "ruler", iconPale: true, title: "身高") {
                            Text("\(profile.map { String(Int($0.heightCm.rounded())) } ?? "170") cm")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color("TextSecondary"))
                            chevron
                        }
                        .onTapGesture {
                            heightText = profile.map { String(Int($0.heightCm.rounded())) } ?? "170"
                            showHeightEditor = true
                        }
                    }
                    .card()

                    // 提醒
                    groupTitle("提醒")
                    VStack(spacing: 0) {
                        HStack(spacing: 11) {
                            roundIcon("bell", pale: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("记录提醒")
                                    .font(.system(size: 14))
                                Text(reminderSubtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                            Spacer()
                            Toggle("", isOn: reminderBinding)
                                .labelsHidden()
                                .tint(Color("BrandGreen"))
                        }
                        .frame(minHeight: 64)
                        .padding(.horizontal, 14)
                        Divider().padding(.leading, 57)
                        row(icon: "clock", iconPale: true, title: "提醒时间") {
                            Text(reminderCountText)
                                .font(.system(size: 12))
                                .foregroundStyle(Color("TextSecondary"))
                            chevron
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { showReminders = true }
                    }
                    .card()

                    // 数据与隐私
                    groupTitle("数据与隐私")
                    VStack(spacing: 0) {
                        Button {
                            exportCSV()
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("square.and.arrow.up", pale: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("导出 CSV")
                                        .font(.system(size: 14))
                                    Text("导出全部体重记录")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color("TextSecondary"))
                                }
                                Spacer()
                                chevron
                            }
                            .frame(minHeight: 64)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 57)
                        HStack(spacing: 11) {
                            roundIcon("lock", pale: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("面容 ID / 触控 ID 解锁")
                                    .font(.system(size: 14))
                                Text(biometricSubtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                            Spacer()
                            Text(profile?.biometricLockEnabled == true ? String(localized: "已开启") : String(localized: "未开启"))
                                .font(.system(size: 10))
                                .foregroundStyle(profile?.biometricLockEnabled == true ? Color("BrandGreen") : Color("TextSecondary"))
                            Toggle("", isOn: biometricBinding)
                                .labelsHidden()
                                .tint(Color("BrandGreen"))
                        }
                        .frame(minHeight: 64)
                        .padding(.horizontal, 14)
                    }
                    .card()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .alert("我的目标", isPresented: $showGoalEditor) {
            TextField("58.0", text: $goalText)
                .keyboardType(.decimalPad)
            Button(String(localized: "确定")) { saveGoal() }
            Button(String(localized: "取消"), role: .cancel) {}
        }
        .alert("身高", isPresented: $showHeightEditor) {
            TextField("170", text: $heightText)
                .keyboardType(.numberPad)
            Button(String(localized: "确定")) { saveHeight() }
            Button(String(localized: "取消"), role: .cancel) {}
        }
        .alert(String(localized: "生物识别不可用"), isPresented: $showBiometricUnavailableAlert) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: {
            Text("请先在系统设置中开启面容 ID 或触控 ID")
        }
        .alert("记录提醒", isPresented: $showNotificationDeniedAlert) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: {
            Text("通知权限被拒绝,请在系统设置中开启")
        }
        .sheet(isPresented: $showReminders) {
            RemindersView()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]) {
                showToastMessage(String(localized: "已导出「%@」")
                    .replacingOccurrences(of: "%@", with: item.url.lastPathComponent))
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color("TextPrimary").opacity(0.88), in: RoundedRectangle(cornerRadius: 13))
                    .padding(.bottom, 30)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showToast)
    }

    // MARK: - 绑定

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { profile?.reminderEnabled ?? true },
            set: { newValue in
                profile?.reminderEnabled = newValue
                try? context.save()
                if newValue {
                    Task {
                        let granted = await NotificationService.requestAuthorization()
                        if granted {
                            await NotificationService.sync(times: reminderTimes, enabled: true)
                        } else {
                            profile?.reminderEnabled = false
                            try? context.save()
                            showNotificationDeniedAlert = true
                        }
                    }
                } else {
                    Task { await NotificationService.cancelAll() }
                }
            }
        )
    }

    /// 按一天内时间排序的提醒时间
    private var reminderTimes: [(id: UUID, hour: Int, minute: Int)] {
        reminders
            .sorted { $0.minutesOfDay < $1.minutesOfDay }
            .map { (id: $0.id, hour: $0.hour, minute: $0.minute) }
    }

    /// 副标题:最多列出 3 个时间,更多则加省略
    private var reminderSubtitle: String {
        let sorted = reminders.sorted { $0.minutesOfDay < $1.minutesOfDay }
        guard !sorted.isEmpty else { return String(localized: "尚未设置提醒时间") }
        let shown = sorted.prefix(3).map(\.timeText).joined(separator: "、")
        let suffix = sorted.count > 3 ? "…" : ""
        return String(localized: "每天 %@").replacingOccurrences(of: "%@", with: shown + suffix)
    }

    private var reminderCountText: String {
        String(localized: "%lld 条").replacingOccurrences(of: "%lld", with: String(reminders.count))
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { profile?.biometricLockEnabled ?? false },
            set: { newValue in
                if newValue {
                    guard BiometricLockService.canEvaluate() else {
                        showBiometricUnavailableAlert = true
                        return
                    }
                }
                profile?.biometricLockEnabled = newValue
                try? context.save()
            }
        )
    }

    private var biometricSubtitle: String {
        if profile?.biometricLockEnabled == true {
            return "\(BiometricLockService.biometricTypeName) · \(String(localized: "后台自动锁定"))"
        }
        return String(localized: "为你的健康数据增加保护")
    }

    private var goalValueText: String {
        profile.map { "\(StatsCalculator.format1($0.goalWeight)) kg" } ?? "—"
    }

    // MARK: - 操作

    private func saveGoal() {
        guard let value = Double(goalText), value >= 30, value <= 300 else { return }
        profile?.goalWeight = value
        try? context.save()
    }

    private func saveHeight() {
        guard let value = Double(heightText), value > 50, value < 250 else { return }
        profile?.heightCm = value
        try? context.save()
    }

    private func exportCSV() {
        guard let url = CSVExporter.exportWeightCSV(from: entries) else { return }
        shareItem = ShareItem(url: url)
    }

    private func showToastMessage(_ text: String) {
        toastText = text
        withAnimation { showToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation { showToast = false }
        }
    }

    // MARK: - 组件

    private func groupTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color("TextSecondary"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 11)
            .padding(.bottom, 7)
            .padding(.top, 20)
    }

    private func row(icon: String, iconPale: Bool, title: LocalizedStringKey, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 11) {
            roundIcon(icon, pale: iconPale)
            Text(title)
                .font(.system(size: 14))
            Spacer()
            trailing()
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 14)
    }

    private func roundIcon(_ systemName: String, pale: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(pale ? Color("TextSecondary") : Color("BrandGreen"))
            .frame(width: 32, height: 32)
            .background(pale ? Color("PageBackground") : Color("BrandGreen").opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color("TextSecondary"))
    }
}

private extension View {
    func card() -> some View {
        background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 17))
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [MetricEntry.self, UserProfile.self, Reminder.self], inMemory: true)
}
