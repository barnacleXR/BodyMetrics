import SwiftUI
import SwiftData

/// 编辑一条已有记录。
///
/// 删除走"删除 + 撤销 toast"而不是二次确认弹窗:确认弹窗打断操作流,
/// 撤销既不打断又真能救回来。撤销靠删除前留下的 draft 快照重建。
struct EditRecordSheet: View {
    let target: DayRecordsList.RecordTarget
    let date: Date
    /// (提示文案, 撤销操作)
    let onFinished: (String, (() -> Void)?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title) { dismiss() }
            ScrollView {
                content
                    .padding(.horizontal, 23)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Color("PageBackground"))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var title: LocalizedStringKey {
        switch target {
        case .food: return "编辑食物"
        case .strength: return "编辑力量记录"
        case .cardio: return "编辑有氧记录"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch target {
        case .food(let item):
            FoodFormView(
                initial: (FoodDraft(from: item), item.meal?.type ?? .snack),
                onSubmit: { draft, mealType in
                    DayLogService.updateFood(item, with: draft, mealType: mealType, on: date, in: context)
                    finish(String(localized: "已保存"), undo: nil)
                },
                onDelete: {
                    // 先把 context 取成局部常量再交给撤销闭包。撤销是在弹层关闭之后才执行的,
                    // 那时 @Environment 已不再挂在任何视图上,闭包里再读 self.context 拿到的
                    // 是一个没接容器的空 context——写入会静默进虚空
                    let modelContext = context
                    let snapshot = FoodDraft(from: item)
                    let mealType = item.meal?.type ?? .snack
                    let name = item.name
                    let day = date
                    DayLogService.deleteFood(item, in: modelContext)
                    finish(String(localized: "已删除 \(name)")) {
                        DayLogService.addFood(snapshot, mealType: mealType, on: day, in: modelContext)
                    }
                }
            )
        case .strength(let workout):
            StrengthFormView(
                initial: StrengthDraft(from: workout),
                onSubmit: { draft in
                    DayLogService.updateStrength(workout, with: draft, in: context)
                    finish(String(localized: "已保存"), undo: nil)
                },
                onDelete: {
                    let modelContext = context
                    let snapshot = StrengthDraft(from: workout)
                    let name = workout.name
                    let day = date
                    DayLogService.deleteStrength(workout, in: modelContext)
                    finish(String(localized: "已删除 \(name)")) {
                        DayLogService.addStrength(snapshot, on: day, in: modelContext)
                    }
                }
            )
        case .cardio(let session):
            CardioFormView(
                initial: CardioDraft(from: session),
                onSubmit: { draft in
                    DayLogService.updateCardio(session, with: draft, in: context)
                    finish(String(localized: "已保存"), undo: nil)
                },
                onDelete: {
                    let modelContext = context
                    let snapshot = CardioDraft(from: session)
                    let name = session.name
                    let day = date
                    DayLogService.deleteCardio(session, in: modelContext)
                    finish(String(localized: "已删除 \(name)")) {
                        DayLogService.addCardio(snapshot, on: day, in: modelContext)
                    }
                }
            )
        }
    }

    private func finish(_ message: String, undo: (() -> Void)?) {
        dismiss()
        onFinished(message, undo)
    }
}
