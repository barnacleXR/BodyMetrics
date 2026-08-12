import SwiftUI
import SwiftData

/// 某一天的完整记录(日历里点开)。只读 + 备注可改,要改记录回记录页
struct DaySummarySheet: View {
    let date: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var dayLogs: [DayLog]
    @Query(sort: \NutritionTarget.effectiveFrom) private var targets: [NutritionTarget]

    @State private var noteText = ""
    @State private var didLoadNote = false

    private let calendar = Calendar.current

    private var dayLog: DayLog? {
        dayLogs.first { calendar.isDate($0.dayStart, inSameDayAs: date) }
    }

    private var totals: DayTotals {
        dayLog.map { NutritionCalculator.totals(for: $0) } ?? .zero
    }

    private var weightEntries: [MetricEntry] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return entries
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: LocalizedStringKey(date.formatted(.dateTime.month().day().weekday(.wide)))) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    if !weightEntries.isEmpty { weightSection }
                    DayRecordsList(dayLog: dayLog, emptyText: "这一天没有饮食与训练记录。") { _ in }
                    noteSection
                }
                .padding(.horizontal, 23)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            guard !didLoadNote else { return }
            didLoadNote = true
            noteText = dayLog?.note ?? ""
        }
    }

    private var summaryCard: some View {
        let target = NutritionCalculator.target(on: date, in: targets, calendar: calendar)?.kcal ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(totals.macros.kcal.rounded()))")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color("TextPrimary"))
                Text(target > 0 ? "/ \(Int(target)) kcal" : "kcal")
                    .font(.system(size: 13))
                    .foregroundStyle(Color("TextSecondary"))
                Spacer()
                if target > 0 {
                    Text(NutritionCalculator.isKcalOnTarget(totals.macros.kcal, target: target)
                         ? String(localized: "达标") : String(localized: "偏离"))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            NutritionCalculator.isKcalOnTarget(totals.macros.kcal, target: target)
                                ? Color("BrandGreen").opacity(0.15)
                                : Color(red: 0.85, green: 0.6, blue: 0.15).opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            NutritionCalculator.isKcalOnTarget(totals.macros.kcal, target: target)
                                ? Color("BrandGreen")
                                : Color(red: 0.72, green: 0.45, blue: 0.1)
                        )
                }
            }
            Text("P \(StatsCalculator.format1(totals.macros.proteinG)) · F \(StatsCalculator.format1(totals.macros.fatG)) · C \(StatsCalculator.format1(totals.macros.carbG))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color("TextSecondary"))
            if totals.burnedKcal > 0 || totals.volumeKg > 0 {
                Text("\(String(localized: "训练消耗")) \(Int(totals.burnedKcal)) kcal · \(String(localized: "容量")) \(Int(totals.volumeKg)) kg")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "体重")
            VStack(spacing: 0) {
                ForEach(Array(weightEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 14) }
                    HStack {
                        Text(entry.metric.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Color("TextSecondary"))
                        Text(entry.date.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color("TextSecondary"))
                        Spacer()
                        Text("\(StatsCalculator.format1(entry.value)) \(entry.metric.unit)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color("TextPrimary"))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                }
            }
            .cardBackground()
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "备注")
            TextField(String(localized: "睡眠、状态、外食场合…"), text: $noteText, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(2...5)
                .padding(12)
                .cardBackground(cornerRadius: 13)
                .onChange(of: noteText) { _, newValue in
                    DayLogService.setNote(newValue, on: date, in: context, calendar: calendar)
                }
        }
    }
}
