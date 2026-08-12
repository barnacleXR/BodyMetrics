import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @Query private var foodPresets: [FoodPreset]
    @Query private var customExercises: [CustomExercise]
    @Query(sort: \NutritionTarget.effectiveFrom) private var targets: [NutritionTarget]
    @Environment(\.modelContext) private var context

    @State private var showGoalPlanner = false
    @State private var showFoodLibrary = false
    @State private var showExerciseLibrary = false
    @State private var showAIExport = false
    @State private var showImporter = false
    @State private var showWipeConfirm = false
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

                    // 目标
                    groupTitle("目标")
                    VStack(spacing: 0) {
                        Button {
                            showGoalPlanner = true
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("target", pale: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("每日目标")
                                        .font(.system(size: 14))
                                    Text(targetSubtitle)
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
                        row(icon: "flag", iconPale: true, title: "目标体重") {
                            Text(goalValueText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color("TextSecondary"))
                            chevron
                        }
                        .contentShape(Rectangle())
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            heightText = profile.map { String(Int($0.heightCm.rounded())) } ?? "170"
                            showHeightEditor = true
                        }
                    }
                    .card()

                    // 偏好
                    groupTitle("偏好")
                    VStack(spacing: 0) {
                        HStack(spacing: 11) {
                            roundIcon("flame", pale: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("训练消耗回补额度")
                                    .font(.system(size: 14))
                                Text("活动系数已含日常活动,开启会双重计算")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                            Spacer()
                            Toggle("", isOn: addBurnedBinding)
                                .labelsHidden()
                                .tint(Color("BrandGreen"))
                        }
                        .frame(minHeight: 64)
                        .padding(.horizontal, 14)
                        Divider().padding(.leading, 57)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 11) {
                                roundIcon("circle.lefthalf.filled", pale: true)
                                Text("外观")
                                    .font(.system(size: 14))
                                Spacer()
                            }
                            Picker("", selection: themeBinding) {
                                ForEach(ThemePreference.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .card()

                    // 资料库
                    groupTitle("资料库")
                    VStack(spacing: 0) {
                        Button {
                            showFoodLibrary = true
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("fork.knife", pale: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("常用食物")
                                        .font(.system(size: 14))
                                    Text("记录过的会自动入库,可在这里改错值")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color("TextSecondary"))
                                }
                                Spacer()
                                Text("\(foodPresets.count)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Color("TextSecondary"))
                                chevron
                            }
                            .frame(minHeight: 64)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 57)
                        Button {
                            showExerciseLibrary = true
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("dumbbell", pale: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("动作库")
                                        .font(.system(size: 14))
                                    Text(exerciseLibrarySubtitle)
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
                            showAIExport = true
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("sparkles", pale: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("导出给 AI 分析")
                                        .font(.system(size: 14))
                                    Text("含体重、饮食、训练与实测代谢")
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
                        Button {
                            exportBackup()
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("arrow.down.doc", pale: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("导出完整备份")
                                        .font(.system(size: 14))
                                    Text("数据只存在这台设备,建议定期备份")
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
                        Button {
                            showImporter = true
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("arrow.up.doc", pale: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("导入备份")
                                        .font(.system(size: 14))
                                    Text("会先清空当前数据再恢复")
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
                        Button {
                            exportCSV()
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("tablecells", pale: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("导出 CSV")
                                        .font(.system(size: 14))
                                    Text("体重与每日饮食两份")
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
                        Divider().padding(.leading, 57)
                        Button {
                            showWipeConfirm = true
                        } label: {
                            HStack(spacing: 11) {
                                roundIcon("trash", pale: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("清空全部数据")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.red.opacity(0.9))
                                    Text("不可撤销,建议先导出备份")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color("TextSecondary"))
                                }
                                Spacer()
                            }
                            .frame(minHeight: 64)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .card()

                    Text("schema v\(BackupService.formatVersion) · \(dayLogCount) 天记录")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                        .opacity(0.7)
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
        .sheet(isPresented: $showGoalPlanner) {
            NutritionGoalView()
        }
        .sheet(isPresented: $showFoodLibrary) {
            FoodLibraryView()
        }
        .sheet(isPresented: $showExerciseLibrary) {
            ExerciseLibraryView()
        }
        .sheet(isPresented: $showAIExport) {
            AIExportView()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog(
            Text("清空全部数据?"),
            isPresented: $showWipeConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "清空"), role: .destructive) {
                BackupService.wipe(context)
                showToastMessage(String(localized: "已清空"))
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text("此操作不可撤销,建议先导出备份。")
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
    private var reminderTimes: [(id: UUID, hour: Int, minute: Int, kind: ReminderKind)] {
        reminders
            .sorted { $0.minutesOfDay < $1.minutesOfDay }
            .map { (id: $0.id, hour: $0.hour, minute: $0.minute, kind: $0.kind) }
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

    /// 已设目标时显示热量与速度,没设时提示去设
    private var targetSubtitle: String {
        guard let current = NutritionCalculator.target(on: .now, in: targets) else {
            return String(localized: "尚未设定,由目标体重与速度推算")
        }
        let rate = profile?.weeklyRateKg ?? 0
        let rateText = rate == 0
            ? String(localized: "维持")
            : "\(rate < 0 ? "−" : "+")\(StatsCalculator.format1(abs(rate))) kg/\(String(localized: "周"))"
        return "\(Int(current.kcal)) kcal · \(current.macros.compactSummaryText) · \(rateText)"
    }

    private var exerciseLibrarySubtitle: String {
        let builtin = ExerciseCatalog.strength.count + ExerciseCatalog.cardio.count
        let hidden = profile?.hiddenBuiltinExerciseIDs.count ?? 0
        var text = String(localized: "\(builtin) 个内置 · 自定义 \(customExercises.count) 个")
        if hidden > 0 { text += String(localized: " · 已隐藏 \(hidden)") }
        return text
    }

    private var addBurnedBinding: Binding<Bool> {
        Binding(
            get: { profile?.addBurnedToBudget ?? false },
            set: { newValue in
                profile?.addBurnedToBudget = newValue
                try? context.save()
            }
        )
    }

    private var themeBinding: Binding<ThemePreference> {
        Binding(
            get: { profile?.themePreference ?? .system },
            set: { newValue in
                profile?.themePreference = newValue
                try? context.save()
            }
        )
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

    private var dayLogCount: Int {
        (try? context.fetchCount(FetchDescriptor<DayLog>())) ?? 0
    }

    private func exportCSV() {
        guard let url = CSVExporter.exportCombinedCSV(
            entries: entries,
            dayLogs: (try? context.fetch(FetchDescriptor<DayLog>())) ?? [],
            targets: targets
        ) else { return }
        shareItem = ShareItem(url: url)
    }

    private func exportBackup() {
        let json = BackupService.exportJSON(from: context)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bodymetrics-backup-\(formatter.string(from: .now)).json")
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            showToastMessage(String(localized: "导出失败"))
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            showToastMessage(String(localized: "没有选择文件"))
            return
        }
        // 文件来自文件 App,必须先取得安全作用域访问权限
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            showToastMessage(String(localized: "无法读取文件"))
            return
        }
        switch BackupService.importJSON(text, into: context) {
        case .restored(let days, let entries):
            showToastMessage(String(localized: "已恢复 \(days) 天记录、\(entries) 条体重"))
        case .prototypeSummaryOnly(let days):
            showToastMessage(String(localized: "分析包只含汇总,仅恢复了 \(days) 天的备注"))
        case .failed(let reason):
            showToastMessage(reason)
        }
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
        .modelContainer(for: AppSchema.models, inMemory: true)
}
