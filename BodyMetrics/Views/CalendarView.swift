import SwiftUI
import SwiftData

/// 日历页:月视图(周日开头,周日起始)+ 当日详情 + 编辑
struct CalendarView: View {
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Environment(\.modelContext) private var context

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showEditSheet = false

    private var calendar: Calendar { Calendar.current }

    // MARK: - 月网格计算

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.year().month())
    }

    /// 当月 1 号是周几(1=周日)前的偏移格数
    private var firstWeekdayOffset: Int {
        let comps = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let first = calendar.date(from: comps) else { return 0 }
        return calendar.component(.weekday, from: first) - 1
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
    }

    /// 网格总格数(补齐整周)
    private var gridCount: Int {
        let total = firstWeekdayOffset + daysInMonth
        return ((total + 6) / 7) * 7
    }

    /// index 对应的日期;offset 前/后为邻月置灰区,返回 nil
    private func day(for index: Int) -> Date? {
        guard index >= firstWeekdayOffset, index < firstWeekdayOffset + daysInMonth else { return nil }
        var comps = calendar.dateComponents([.year, .month], from: visibleMonth)
        comps.day = index - firstWeekdayOffset + 1
        return calendar.date(from: comps)
    }

    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = next
        }
    }

    // MARK: - 详情数据

    private var selectedValue: Double? {
        StatsCalculator.latestValue(on: selectedDay, metric: .weight, in: entries)
    }

    private var detailTitle: String {
        let dateText = selectedDay.formatted(.dateTime.month().day())
        if calendar.isDateInToday(selectedDay) {
            return "\(dateText) · \(String(localized: "今天"))"
        }
        return dateText
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    monthHeader
                    weekHeader
                    calendarGrid
                    detailBar
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            LogSheetView(
                initialMetric: .weight,
                targetDate: selectedDay,
                initialValue: selectedValue.map { StatsCalculator.format1($0) }
            )
        }
    }

    // MARK: - 月标题

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color("BrandGreen").opacity(0.12))
                            .frame(width: 33, height: 33)
                    )
                    .foregroundStyle(Color("BrandGreen"))
            }
            .accessibilityLabel(String(localized: "上月"))
            Spacer()
            Text(monthTitle)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button {
                changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color("BrandGreen").opacity(0.12))
                            .frame(width: 33, height: 33)
                    )
                    .foregroundStyle(Color("BrandGreen"))
            }
            .accessibilityLabel(String(localized: "下月"))
        }
        .padding(.vertical, 16)
    }

    // MARK: - 周标题(周日开头,周日红/周六蓝)

    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(calendar.veryShortStandaloneWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(weekdayColor(index))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 7)
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return Color.red.opacity(0.8) }
        if index == 6 { return Color.blue.opacity(0.8) }
        return Color("TextSecondary")
    }

    // MARK: - 日期网格

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(0..<gridCount, id: \.self) { index in
                if let date = day(for: index) {
                    dayCell(date: date)
                } else {
                    Color.clear.frame(height: 74)
                }
            }
        }
        .background(Color("CardBackground"))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color("CardBackground"), lineWidth: 0)
        )
    }

    private func dayCell(date: Date) -> some View {
        let value = StatsCalculator.latestValue(on: date, metric: .weight, in: entries)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        return Button {
            selectedDay = date
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color("BrandGreen") : Color("TextPrimary"))
                if let value {
                    Text(StatsCalculator.format1(value))
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(6)
            .background(
                Rectangle()
                    .fill(isSelected ? Color("BrandGreen").opacity(0.10) : Color.clear)
            )
            .overlay(
                Rectangle()
                    .stroke(isToday ? Color("BrandGreen") : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 当日详情

    private var detailBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(detailTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color("TextSecondary"))
                Text(selectedValue.map { "\(StatsCalculator.format1($0)) kg" } ?? "—")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color("BrandGreen"))
            }
            Spacer()
            Button(String(localized: "编辑")) {
                showEditSheet = true
            }
            .font(.system(size: 12))
            .foregroundStyle(Color("BrandGreen"))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color("BrandGreen").opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(16)
        .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 17))
        .padding(.top, 18)
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [MetricEntry.self, UserProfile.self], inMemory: true)
}
