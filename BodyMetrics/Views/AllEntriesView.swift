import SwiftUI
import SwiftData

/// 全部记录:按时间倒序列出所有记录,左滑删除 / 编辑模式批量删除;删空到 0 条也是合法状态
struct AllEntriesView: View {
    @Query(sort: \MetricEntry.date, order: .reverse) private var entries: [MetricEntry]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.id) { entry in
                    row(entry)
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        String(localized: "尚未记录"),
                        systemImage: "tray",
                        description: Text("在记录页添加第一条记录")
                    )
                }
            }
            .navigationTitle(Text("全部记录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !entries.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
    }

    private func row(_ entry: MetricEntry) -> some View {
        HStack(spacing: 11) {
            Text(entry.metric.label)
                .font(.system(size: 11))
                .foregroundStyle(Color("BrandGreen"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color("BrandGreen").opacity(0.12), in: Capsule())
            Text(entry.date.formatted(.dateTime.month().day().hour().minute()))
                .font(.system(size: 13))
                .foregroundStyle(Color("TextSecondary"))
            Spacer()
            Text("\(StatsCalculator.format1(entry.value)) \(entry.metric.unit)")
                .font(.system(size: 14, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color("TextPrimary"))
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(entries[index])
        }
        try? context.save()
    }
}

#Preview {
    AllEntriesView()
        .modelContainer(for: AppSchema.models, inMemory: true)
}
