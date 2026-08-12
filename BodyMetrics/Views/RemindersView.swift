import SwiftUI
import SwiftData

/// 提醒时间管理:可添加多条、逐条改时间、左滑删除
struct RemindersView: View {
    @Query(sort: \Reminder.hour) private var reminders: [Reminder]
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false
    /// nil 表示新建
    @State private var editingReminder: Reminder?
    @State private var editorTime: Date = Date()

    private var profile: UserProfile? { profiles.first }
    /// 按一天内的时间排序(@Query 只按 hour 排,同小时内还要按 minute)
    private var sortedReminders: [Reminder] {
        reminders.sorted { $0.minutesOfDay < $1.minutesOfDay }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedReminders, id: \.id) { reminder in
                        Button {
                            beginEdit(reminder)
                        } label: {
                            HStack {
                                Text(reminder.timeText)
                                    .font(.system(size: 22, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(Color("TextPrimary"))
                                Text("每天")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color("TextSecondary"))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    if profile?.reminderEnabled == false {
                        Text("记录提醒总开关已关闭,以下时间暂不会发送通知。")
                    } else {
                        Text("每条提醒每天在设定时间重复发送。")
                    }
                }
            }
            .overlay {
                if reminders.isEmpty {
                    ContentUnavailableView(
                        String(localized: "尚未设置提醒"),
                        systemImage: "bell.slash",
                        description: Text("点右上角加号添加一个提醒时间")
                    )
                }
            }
            .navigationTitle(Text("提醒时间"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !reminders.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        beginEdit(nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "添加提醒"))
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .sheet(isPresented: $showEditor) {
                editorSheet
            }
        }
    }

    private var editorSheet: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: $editorTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .navigationTitle(Text(editingReminder == nil ? "添加提醒" : "修改时间"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "取消")) { showEditor = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成")) { commitEdit() }
                }
            }
            .presentationDetents([.height(300)])
        }
    }

    // MARK: - 操作

    private func beginEdit(_ reminder: Reminder?) {
        editingReminder = reminder
        var components = DateComponents()
        components.hour = reminder?.hour ?? 8
        components.minute = reminder?.minute ?? 0
        editorTime = Calendar.current.date(from: components) ?? Date()
        showEditor = true
    }

    private func commitEdit() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: editorTime)
        guard let hour = components.hour, let minute = components.minute else { return }

        // 已有同一时间的提醒时不重复添加(同一条自身除外)
        let duplicate = reminders.contains {
            $0.hour == hour && $0.minute == minute && $0.id != editingReminder?.id
        }
        if duplicate {
            showEditor = false
            return
        }

        if let editingReminder {
            editingReminder.hour = hour
            editingReminder.minute = minute
        } else {
            context.insert(Reminder(hour: hour, minute: minute))
        }
        try? context.save()
        showEditor = false
        syncNotifications()
    }

    private func delete(at offsets: IndexSet) {
        let list = sortedReminders
        for index in offsets {
            context.delete(list[index])
        }
        try? context.save()
        syncNotifications()
    }

    private func syncNotifications() {
        let times = sortedReminders.map { (id: $0.id, hour: $0.hour, minute: $0.minute) }
        let enabled = profile?.reminderEnabled ?? true
        Task { await NotificationService.sync(times: times, enabled: enabled) }
    }
}

#Preview {
    RemindersView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
