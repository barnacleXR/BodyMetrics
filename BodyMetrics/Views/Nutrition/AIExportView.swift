import SwiftUI
import SwiftData
import UIKit

/// 导出给 AI 分析 + 把回复存档。
///
/// 维持"复制出去、粘结论回来"的手动流程:App 不联网是核心原则,
/// 在这里直连 API 会把它打破。
struct AIExportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Query private var dayLogs: [DayLog]
    @Query private var profiles: [UserProfile]
    @Query(sort: \NutritionTarget.effectiveFrom) private var targets: [NutritionTarget]
    @Query(sort: \AIReport.createdAt, order: .reverse) private var reports: [AIReport]

    enum ExportRange: String, CaseIterable, Hashable {
        case day, week, month, all

        var label: String {
            switch self {
            case .day: return String(localized: "当天")
            case .week: return String(localized: "7 天")
            case .month: return String(localized: "30 天")
            case .all: return String(localized: "全部")
            }
        }
    }

    enum ExportFormat: String, CaseIterable, Hashable {
        case markdown, json

        var label: String {
            switch self {
            case .markdown: return "Markdown"
            case .json: return "JSON"
            }
        }

        var fileExtension: String { self == .markdown ? "md" : "json" }
    }

    @State private var range: ExportRange = .month
    /// 默认 Markdown:这份内容是粘进聊天框给模型看的,不被程序解析。
    /// 同样的数据 token 少得多,用户自己也能扫一眼确认对不对
    @State private var format: ExportFormat = .markdown
    @State private var prompt = AIExportBuilder.prompt(singleDay: false, mentionsJSONFields: false)
    @State private var showArchiveSheet = false
    @State private var archiveText = ""
    @State private var toastMessage: ToastMessage?
    @State private var shareItem: ShareItem?

    private let calendar = Calendar.current
    private var profile: UserProfile? { profiles.first }

    private var dateRange: (from: Date, to: Date) {
        let today = calendar.startOfDay(for: .now)
        switch range {
        case .day:
            return (today, today)
        case .week:
            return (calendar.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .month:
            return (calendar.date(byAdding: .day, value: -29, to: today) ?? today, today)
        case .all:
            let earliestLog = dayLogs.map(\.dayStart).min()
            let earliestEntry = entries.map(\.date).min()
            let earliest = [earliestLog, earliestEntry].compactMap { $0 }.min() ?? today
            return (calendar.startOfDay(for: earliest), today)
        }
    }

    private var fusedDays: [FusedDay] {
        FusedSeriesBuilder.build(
            from: dateRange.from, to: dateRange.to,
            entries: entries, dayLogs: dayLogs, targets: targets, calendar: calendar
        )
    }

    private var formulaTDEE: Double {
        guard let profile, let age = profile.age,
              let weight = entries.filter({ $0.metric == .weight }).max(by: { $0.date < $1.date })?.value
        else { return 0 }
        return NutritionCalculator.tdee(
            sex: profile.sex, weightKg: weight, heightCm: profile.heightCm,
            age: age, activityLevel: profile.activityLevel
        )
    }

    private var payload: AIExportBuilder.Payload {
        let analysisDays: [FusedDay] = {
            let today = calendar.startOfDay(for: .now)
            guard let start = calendar.date(byAdding: .day, value: -27, to: today) else { return [] }
            return FusedSeriesBuilder.build(
                from: start, to: today,
                entries: entries, dayLogs: dayLogs, targets: targets, calendar: calendar
            )
        }()
        return AIExportBuilder.build(
            days: fusedDays, dayLogs: dayLogs, entries: entries, targets: targets,
            profile: profile,
            adaptive: EnergyBalanceService.adaptiveTDEE(
                weights: StatsCalculator.weightSamples(from: entries),
                intakes: FusedSeriesBuilder.dailyIntakes(from: analysisDays),
                formulaTDEE: formulaTDEE, calendar: calendar
            ),
            formulaTDEE: formulaTDEE,
            prompt: prompt,
            calendar: calendar
        )
    }

    /// 按当前格式渲染出的正文
    private var exportText: String {
        format == .markdown
            ? MarkdownExportRenderer.render(payload)
            : AIExportBuilder.encode(payload)
    }

    private var sizeKB: Int { max(1, exportText.utf8.count / 1024) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "导出给 AI 分析") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("", selection: $range) {
                        ForEach(ExportRange.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 10)
                    .onChange(of: range) { _, _ in syncPromptIfUntouched() }

                    Picker("", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 6)
                    .onChange(of: format) { _, _ in syncPromptIfUntouched() }

                    Text(format == .markdown
                         ? "贴给 AI 用 Markdown 就够了,同样的数据更省 token,你自己也读得懂。"
                         : "JSON 适合喂给脚本处理;贴进对话框会多花不少 token。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineSpacing(3)
                        .padding(.bottom, 16)

                    LabeledField(label: "分析提示词(会一并附在导出内容里)") {
                        TextField("", text: $prompt, axis: .vertical)
                            .font(.system(size: 13))
                            .lineLimit(5...12)
                            .padding(12)
                            .cardBackground(cornerRadius: 13)
                    }

                    rangeSummary
                    exportButtons.padding(.top, 4)
                    archiveSection.padding(.top, 24)
                }
                .padding(.horizontal, 23)
                .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .toast($toastMessage)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]) {}
        }
        .sheet(isPresented: $showArchiveSheet) { archiveSheet }
    }

    private var rangeSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(payload.range.from) ~ \(payload.range.to) · \(String(localized: "有数据")) \(payload.range.daysWithData) \(String(localized: "天")) · \(String(localized: "约")) \(sizeKB) KB")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color("TextSecondary"))
            if payload.range.daysWithData == 0 {
                Text("这个范围里没有记录,导出的会是一份空数据。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.1))
            }
            if payload.profile.measuredTdee != nil {
                Text("已包含实测代谢与体重响应,AI 能对照着看吃了多少和体重怎么走。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("BrandGreen"))
            }
        }
        .padding(.bottom, 14)
    }

    private var exportButtons: some View {
        HStack(spacing: 10) {
            GhostButton(title: "分享文件", systemImage: "square.and.arrow.up") {
                let base = payload.range.from == payload.range.to
                    ? "bodymetrics-\(payload.range.from)"
                    : "bodymetrics-\(payload.range.from)_\(payload.range.to)"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(base).\(format.fileExtension)")
                do {
                    try exportText.write(to: url, atomically: true, encoding: .utf8)
                    shareItem = ShareItem(url: url)
                } catch {
                    toastMessage = ToastMessage(text: String(localized: "导出失败"))
                }
            }
            Button {
                UIPasteboard.general.string = exportText
                toastMessage = ToastMessage(text: String(localized: "已复制，粘给 AI 即可"))
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.on.doc").font(.system(size: 14, weight: .medium))
                    Text("复制").font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color("BrandGreen"), in: RoundedRectangle(cornerRadius: 15))
                .foregroundStyle(.white)
            }
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(
                text: "AI 分析存档",
                trailing: AnyView(
                    Button(String(localized: "添加")) {
                        archiveText = ""
                        showArchiveSheet = true
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color("BrandGreen"))
                )
            )
            VStack(spacing: 0) {
                if reports.isEmpty {
                    EmptyHint(text: "把 AI 的回复贴回来存档,\n以后能对照当时的数据回看。")
                } else {
                    ForEach(Array(reports.enumerated()), id: \.element.persistentModelID) { index, report in
                        if index > 0 { Divider().padding(.leading, 14) }
                        reportRow(report)
                    }
                }
            }
            .cardBackground()
        }
    }

    private func reportRow(_ report: AIReport) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color("BrandGreen"))
                .frame(width: 32, height: 32)
                .background(Color("BrandGreen").opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(formatter.string(from: report.rangeFrom)) ~ \(formatter.string(from: report.rangeTo))")
                    .font(.system(size: 13, design: .monospaced))
                Text(report.responseText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
                    .lineSpacing(3)
                Text("\(report.createdAt.formatted(.dateTime.year().month().day())) · \(String(localized: "含数据快照"))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("TextSecondary"))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
            Button {
                context.delete(report)
                try? context.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .accessibilityLabel(String(localized: "删除存档"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
    }

    private var archiveSheet: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "存档 AI 分析") { showArchiveSheet = false }
            VStack(alignment: .leading, spacing: 0) {
                Text("会连同当前导出范围(\(payload.range.from) ~ \(payload.range.to))的数据快照一起存下来,以后回看时能知道结论是基于什么数据得出的。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("TextSecondary"))
                    .lineSpacing(3)
                    .padding(.bottom, 14)
                LabeledField(label: "AI 的回复") {
                    TextField(String(localized: "粘贴到这里"), text: $archiveText, axis: .vertical)
                        .font(.system(size: 13))
                        .lineLimit(8...16)
                        .padding(12)
                        .cardBackground(cornerRadius: 13)
                }
                PrimaryButton(title: "保存", enabled: !archiveText.trimmingCharacters(in: .whitespaces).isEmpty) {
                    saveArchive()
                }
                Spacer()
            }
            .padding(.horizontal, 23)
            .padding(.top, 16)
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func saveArchive() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        context.insert(AIReport(
            rangeFrom: dateRange.from,
            rangeTo: dateRange.to,
            promptUsed: prompt,
            responseText: archiveText.trimmingCharacters(in: .whitespacesAndNewlines),
            // 快照始终存 JSON:存档是给程序回看的,要的是结构完整而非好读
            payloadSnapshot: Data(AIExportBuilder.encode(payload).utf8)
        ))
        try? context.save()
        showArchiveSheet = false
        toastMessage = ToastMessage(text: String(localized: "已存档"))
    }

    /// 区间或格式变化时换用对应的默认提示词,但用户手写过就不动。
    /// 用"当前值是否等于某个默认值"判断有没有被改过,比维护一个 edited 标记更可靠——
    /// 后者在自己写回 prompt 时会被 onChange 误置为 true
    private func syncPromptIfUntouched() {
        guard AIExportBuilder.allDefaultPrompts.contains(prompt) else { return }
        prompt = AIExportBuilder.prompt(
            singleDay: range == .day,
            mentionsJSONFields: format == .json
        )
    }
}
