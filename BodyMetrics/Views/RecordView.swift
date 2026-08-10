import SwiftUI
import SwiftData

/// 记录页(默认首页):今日体重卡片 + 进度区 + 最近记录
struct RecordView: View {
    @Binding var selection: RootTabView.AppTab
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    @State private var showLogSheet = false

    private var profile: UserProfile? { profiles.first }
    private var weightEntries: [MetricEntry] { entries.filter { $0.metric == .weight } }
    private var todayWeight: Double? {
        StatsCalculator.latestValue(on: .now, metric: .weight, in: entries)
    }

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 22) {
                        heroCard
                        progressSection
                        recentSection
                        Button {
                            showLogSheet = true
                        } label: {
                            Text("记录体重")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 49)
                                .background(Color("BrandGreen"), in: RoundedRectangle(cornerRadius: 15))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogSheetView(initialMetric: .weight)
        }
    }

    // MARK: - 页头

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(weekdayLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
                Text("体重")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1)
            }
            Spacer()
            Button {
                selection = .calendar
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color("BrandGreen").opacity(0.12))
                            .frame(width: 37, height: 37)
                    )
                    .foregroundStyle(Color("BrandGreen"))
            }
            .accessibilityLabel(String(localized: "日历"))
        }
        .padding(.horizontal, 21)
        .padding(.top, 8)
        .padding(.bottom, 17)
    }

    private var weekdayLine: String {
        let now = Date.now
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let monthDay = now.formatted(.dateTime.month().day())
        return "\(weekday),\(monthDay)"
    }

    // MARK: - 今日体重卡片

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("今日体重")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(todayWeight.map { StatsCalculator.format1($0) } ?? "--")
                    .font(.system(size: 56, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("kg")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.vertical, 5)
            Divider()
                .overlay(Color.white.opacity(0.18))
            HStack {
                if let delta = StatsCalculator.changeVsYesterday(in: entries) {
                    Label {
                        Text("较昨日 \(StatsCalculator.signedText(delta, unit: "kg"))")
                    } icon: {
                        Image(systemName: delta < 0 ? "arrow.down" : "arrow.up")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.85))
                } else if todayWeight != nil {
                    Text("首次记录")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Spacer()
                if let latest = weightEntries.first(where: { Calendar.current.isDateInToday($0.date) }) {
                    Text(latest.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .padding(.top, 12)
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color("HeroGradientStart"), Color("HeroGradientEnd")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25)
        )
        .shadow(color: Color("BrandGreen").opacity(0.22), radius: 12, y: 6)
    }

    // MARK: - 进度区

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("目标体重")
                .font(.system(size: 13))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.leading, 11)
            VStack(spacing: 0) {
                goalRow
                Divider().padding(.leading, 57)
                weeklyRow
            }
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 17))
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
        guard let current = todayWeight else {
            return String(localized: "距离 \(goalText) 还有 —")
        }
        let remaining = current - profile.goalWeight
        if remaining <= 0 {
            return String(localized: "已达成")
        }
        let remainingText = StatsCalculator.format1(remaining) + " kg"
        return String(localized: "距离 \(goalText) 还有 \(remainingText)")
    }

    private var progressRing: some View {
        let progress = profile.map { StatsCalculator.goalProgress(in: entries, goal: $0.goalWeight) } ?? 0
        return ZStack {
            Circle()
                .stroke(Color("PageBackground"), lineWidth: 4)
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
                Text(state?.label ?? "")
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

    // MARK: - 最近记录

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("最近记录")
                    .font(.system(size: 13))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
                Button(String(localized: "查看全部")) {
                    selection = .calendar
                }
                .font(.system(size: 12))
                .foregroundStyle(Color("BrandGreen"))
            }
            .padding(.horizontal, 11)
            VStack(spacing: 0) {
                let recent = Array(weightEntries.prefix(3))
                ForEach(recent, id: \.id) { entry in
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
                    if entry.id != recent.last?.id {
                        Divider()
                    }
                }
                if recent.isEmpty {
                    Text("尚未记录")
                        .font(.system(size: 13))
                        .foregroundStyle(Color("TextSecondary"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                }
            }
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 17))
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "今天") + " " + date.formatted(.dateTime.hour().minute())
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "昨天") + " " + date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month().day())
    }

    // MARK: - 组件

    private func iconCircle(systemName: String, pale: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(pale ? Color("TextSecondary") : Color("BrandGreen"))
            .frame(width: 32, height: 32)
            .background(pale ? Color("PageBackground") : Color("BrandGreen").opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
    }
}

#Preview {
    RecordView(selection: .constant(.record))
        .modelContainer(for: [MetricEntry.self, UserProfile.self], inMemory: true)
}
