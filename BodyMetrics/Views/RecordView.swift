import SwiftUI
import SwiftData

/// 记录页(默认首页)= 这一天的全部:体重 + 饮食 + 训练 + 备注。
///
/// 日期导航对全部领域同时生效——原来体重只能看今天、翻历史要去日历页,
/// 融合后一处翻页即可,补录也走同一个入口。
struct RecordView: View {
    @Binding var selection: RootTabView.AppTab

    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var profiles: [UserProfile]
    @Query private var dayLogs: [DayLog]
    @Query(sort: \NutritionTarget.effectiveFrom) private var targets: [NutritionTarget]
    @Environment(\.modelContext) private var context

    @State private var viewDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var showEntrySheet = false
    @State private var editTarget: DayRecordsList.RecordTarget?
    @State private var showAllEntries = false
    @State private var toastMessage: ToastMessage?
    @State private var noteText = ""
    @State private var noteLoadedFor: Date?

    private let calendar = Calendar.current
    private var profile: UserProfile? { profiles.first }
    private var isToday: Bool { calendar.isDateInToday(viewDate) }

    private var dayLog: DayLog? {
        dayLogs.first { calendar.isDate($0.dayStart, inSameDayAs: viewDate) }
    }

    private var totals: DayTotals {
        dayLog.map { NutritionCalculator.totals(for: $0) } ?? .zero
    }

    private var activeTarget: MacroTotals? {
        NutritionCalculator.target(on: viewDate, in: targets)?.macros
    }

    private var remaining: RemainingBudget {
        NutritionCalculator.remaining(
            totals: totals,
            target: activeTarget,
            addBurnedToBudget: profile?.addBurnedToBudget ?? false
        )
    }

    private var dayWeight: Double? {
        StatsCalculator.latestValue(on: viewDate, metric: .weight, in: entries, calendar: calendar)
    }

    private var dayWeightTime: Date? {
        let dayStart = calendar.startOfDay(for: viewDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return entries
            .filter { $0.metric == .weight && $0.date >= dayStart && $0.date < dayEnd }
            .max { $0.date < $1.date }?
            .date
    }

    /// 与前一天相比的变化。看历史某天时也成立,不只是"较昨日"
    private var deltaVsPreviousDay: Double? {
        guard let current = dayWeight,
              let previousDate = calendar.date(byAdding: .day, value: -1, to: viewDate),
              let previous = StatsCalculator.latestValue(on: previousDate, metric: .weight, in: entries, calendar: calendar)
        else { return nil }
        return current - previous
    }

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 22) {
                        FusedHeroCard(
                            weight: dayWeight,
                            weightTime: dayWeightTime,
                            deltaVsYesterday: deltaVsPreviousDay,
                            totals: totals,
                            target: activeTarget,
                            remaining: remaining,
                            onSetupTarget: { selection = .settings }
                        )
                        goalSection
                        if totals.burnedKcal > 0 { burnedRow }
                        recordsSection
                        recentWeightSection
                        noteSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                actionBar
            }
        }
        .sheet(isPresented: $showEntrySheet) {
            RecordEntrySheet(date: viewDate) { message in
                toastMessage = ToastMessage(text: message)
            }
        }
        .sheet(item: $editTarget) { target in
            EditRecordSheet(target: target, date: viewDate) { message, undo in
                toastMessage = ToastMessage(text: message, undo: undo)
            }
        }
        .sheet(isPresented: $showAllEntries) { AllEntriesView() }
        .toast($toastMessage, bottomPadding: 86)
        .onAppear(perform: loadNote)
        .onChange(of: viewDate) { _, _ in loadNote() }
    }

    // MARK: - 页头(日期导航)

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(weekdayLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Color("TextSecondary"))
                    if !isToday {
                        Button(String(localized: "回到今天")) {
                            viewDate = calendar.startOfDay(for: .now)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color("BrandGreen"))
                    }
                }
                Text(dayTitle)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1)
            }
            Spacer()
            HStack(spacing: 2) {
                navButton(systemName: "chevron.left", label: String(localized: "前一天")) {
                    shiftDay(-1)
                }
                navButton(systemName: "chevron.right", label: String(localized: "后一天"), disabled: isToday) {
                    shiftDay(1)
                }
                navButton(systemName: "calendar", label: String(localized: "日历")) {
                    selection = .calendar
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 17)
    }

    private func navButton(
        systemName: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color("BrandGreen").opacity(disabled ? 0.06 : 0.12))
                        .frame(width: 34, height: 34)
                )
                .foregroundStyle(Color("BrandGreen").opacity(disabled ? 0.35 : 1))
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    /// 不允许翻到未来
    private func shiftDay(_ offset: Int) {
        guard let next = calendar.date(byAdding: .day, value: offset, to: viewDate),
              next <= calendar.startOfDay(for: .now)
        else { return }
        viewDate = next
    }

    private var dayTitle: String {
        if isToday { return String(localized: "今日") }
        if calendar.isDateInYesterday(viewDate) { return String(localized: "昨天") }
        return viewDate.formatted(.dateTime.month().day())
    }

    private var weekdayLine: String {
        let weekday = viewDate.formatted(.dateTime.weekday(.wide))
        let monthDay = viewDate.formatted(.dateTime.month().day())
        return "\(weekday),\(monthDay)"
    }

    // MARK: - 目标进度

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "目标体重")
            VStack(spacing: 0) {
                goalRow
                Divider().padding(.leading, 57)
                weeklyRow
            }
            .cardBackground()
        }
    }

    private var goalRow: some View {
        HStack(spacing: 11) {
            iconCircle(systemName: "target", pale: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("目标体重")
                    .font(.system(size: 14))
                Text(goalSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Spacer()
            progressRing
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 14)
    }

    private var goalSubtitle: String {
        guard let profile else { return " " }
        let goalText = StatsCalculator.format1(profile.goalWeight) + " kg"
        guard let current = StatsCalculator.latestValue(on: .now, metric: .weight, in: entries) else {
            return String(localized: "距离 \(goalText) 还有 —")
        }
        let remainingKg = current - profile.goalWeight
        if remainingKg <= 0 { return String(localized: "已达成") }
        let remainingText = StatsCalculator.format1(remainingKg) + " kg"
        return String(localized: "距离 \(goalText) 还有 \(remainingText)")
    }

    private var progressRing: some View {
        let progress = profile.map { StatsCalculator.goalProgress(in: entries, goal: $0.goalWeight) } ?? 0
        return ZStack {
            Circle().stroke(Color("PageBackground"), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color("BrandGreen"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color("TextPrimary"))
        }
        .frame(width: 38, height: 38)
    }

    private var weeklyRow: some View {
        let state = StatsCalculator.weeklyState(in: entries)
        return HStack(spacing: 11) {
            iconCircle(systemName: "sparkles", pale: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("本周状态")
                    .font(.system(size: 14))
                Text(state?.label ?? String(localized: "数据不足"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
            }
            Spacer()
            if let state {
                Text(state.deltaText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(deltaColor(state.deltaText))
            }
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 14)
    }

    private func deltaColor(_ text: String) -> Color {
        if text.hasPrefix("−") { return Color("BrandGreen") }
        if text.hasPrefix("+") { return Color.red.opacity(0.8) }
        return Color("TextSecondary")
    }

    // MARK: - 训练消耗

    private var burnedRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "训练消耗")
            HStack(spacing: 11) {
                iconCircle(systemName: "flame", pale: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(totals.burnedKcal)) kcal")
                        .font(.system(size: 14))
                    Text(profile?.addBurnedToBudget == true ? "已回补进今日额度" : "未回补进额度(设置里可开启)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer()
            }
            .frame(minHeight: 58)
            .padding(.horizontal, 14)
            .cardBackground()
        }
    }

    // MARK: - 当日记录

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: isToday ? "今日记录" : "当天记录")
            DayRecordsList(
                dayLog: dayLog,
                emptyText: isToday
                    ? "还没有记录,点下面的按钮开始。"
                    : "这一天还没有记录,点下面的按钮补录。"
            ) { target in
                editTarget = target
            }
        }
    }

    // MARK: - 最近体重

    private var recentWeightSection: some View {
        let recent = Array(entries.filter { $0.metric == .weight }.prefix(3))
        return VStack(alignment: .leading, spacing: 7) {
            SectionLabel(
                text: "最近体重",
                trailing: AnyView(
                    Button(String(localized: "查看全部")) { showAllEntries = true }
                        .font(.system(size: 12))
                        .foregroundStyle(Color("BrandGreen"))
                )
            )
            VStack(spacing: 0) {
                if recent.isEmpty {
                    EmptyHint(text: "尚未记录")
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        HStack {
                            Text(dateLabel(entry.date))
                                .font(.system(size: 13))
                                .foregroundStyle(Color("TextSecondary"))
                            Spacer()
                            Text("\(StatsCalculator.format1(entry.value)) kg")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color("TextPrimary"))
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                    }
                }
            }
            .cardBackground()
        }
    }

    private func dateLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return String(localized: "今天") + " " + date.formatted(.dateTime.hour().minute())
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "昨天") + " " + date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month().day())
    }

    // MARK: - 备注

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "备注")
            TextField(String(localized: "睡眠、状态、外食场合…"), text: $noteText, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(2...5)
                .padding(12)
                .cardBackground(cornerRadius: 13)
                .onChange(of: noteText) { _, newValue in
                    DayLogService.setNote(newValue, on: viewDate, in: context, calendar: calendar)
                }
        }
    }

    /// 切换日期时重新载入备注。用 noteLoadedFor 挡住重复载入,
    /// 否则 onChange 写回会和载入互相打架
    private func loadNote() {
        guard noteLoadedFor != viewDate else { return }
        noteLoadedFor = viewDate
        noteText = dayLog?.note ?? ""
    }

    // MARK: - 底部按钮

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            PrimaryButton(
                title: isToday ? "记录" : "补录到这一天",
                systemImage: "plus"
            ) {
                showEntrySheet = true
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .background(Color("PageBackground"))
    }

    // MARK: - 组件

    private func iconCircle(systemName: String, pale: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(pale ? Color("TextSecondary") : Color("BrandGreen"))
            .frame(width: 32, height: 32)
            .background(
                pale ? Color("PageBackground") : Color("BrandGreen").opacity(0.13),
                in: RoundedRectangle(cornerRadius: 11)
            )
    }
}

#Preview {
    RecordView(selection: .constant(.record))
        .modelContainer(for: AppSchema.models, inMemory: true)
}
