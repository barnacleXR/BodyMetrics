import SwiftUI
import SwiftData

/// 当日记录清单:按餐次分组的饮食 + 力量 + 有氧。点任意一条进入编辑
struct DayRecordsList: View {
    let dayLog: DayLog?
    var emptyText: LocalizedStringKey = "还没有记录,点下面的按钮开始。"
    var onEdit: (RecordTarget) -> Void

    /// 被点中的那一条记录
    enum RecordTarget: Identifiable {
        case food(FoodItem)
        case strength(StrengthWorkout)
        case cardio(CardioSession)

        var id: String {
            switch self {
            case .food(let item): return "f-\(item.persistentModelID.hashValue)"
            case .strength(let w): return "s-\(w.persistentModelID.hashValue)"
            case .cardio(let c): return "c-\(c.persistentModelID.hashValue)"
            }
        }
    }

    private var meals: [Meal] { dayLog?.sortedMeals ?? [] }
    private var strength: [StrengthWorkout] { (dayLog?.strength ?? []).sorted { $0.sortIndex < $1.sortIndex } }
    private var cardio: [CardioSession] { (dayLog?.cardio ?? []).sorted { $0.sortIndex < $1.sortIndex } }
    private var isEmpty: Bool { meals.isEmpty && strength.isEmpty && cardio.isEmpty }

    var body: some View {
        VStack(spacing: 14) {
            if isEmpty {
                EmptyHint(text: emptyText).cardBackground()
            } else {
                ForEach(meals, id: \.persistentModelID) { meal in
                    group(title: LocalizedStringKey(meal.type.label), systemImage: "fork.knife") {
                        ForEach(Array(meal.items.enumerated()), id: \.element.persistentModelID) { index, item in
                            if index > 0 { Divider().padding(.leading, 14) }
                            foodRow(item)
                        }
                    }
                }
                if !strength.isEmpty {
                    group(title: "力量", systemImage: "dumbbell") {
                        ForEach(Array(strength.enumerated()), id: \.element.persistentModelID) { index, workout in
                            if index > 0 { Divider().padding(.leading, 14) }
                            strengthRow(workout)
                        }
                    }
                }
                if !cardio.isEmpty {
                    group(title: "有氧", systemImage: "figure.run") {
                        ForEach(Array(cardio.enumerated()), id: \.element.persistentModelID) { index, session in
                            if index > 0 { Divider().padding(.leading, 14) }
                            cardioRow(session)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 分组

    private func group<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 13))
            }
            .foregroundStyle(Color("TextSecondary"))
            .padding(.leading, 11)
            VStack(spacing: 0) { content() }
                .cardBackground()
        }
    }

    // MARK: - 行

    private func foodRow(_ item: FoodItem) -> some View {
        let macros = item.scaled
        return Button {
            onEdit(.food(item))
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Color("TextPrimary"))
                        .lineLimit(1)
                    Text("\(item.amountText) · P\(StatsCalculator.format1(macros.proteinG)) F\(StatsCalculator.format1(macros.fatG)) C\(StatsCalculator.format1(macros.carbG))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(macros.kcal.rounded()))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color("TextPrimary"))
                Text("kcal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("TextSecondary"))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func strengthRow(_ workout: StrengthWorkout) -> some View {
        let working = workout.orderedSets.filter { !$0.isWarmup }
        return Button {
            onEdit(.strength(workout))
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Color("TextPrimary"))
                        .lineLimit(1)
                    Text(setSummary(working))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(workout.volumeKg)) kg")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color("TextPrimary"))
                    Text("容量")
                        .font(.system(size: 10))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "5×100kg · 5×100kg" 太长,相同组合并成 "2 组 × 5 × 100kg"
    private func setSummary(_ sets: [StrengthSet]) -> String {
        guard !sets.isEmpty else { return String(localized: "只有热身组") }
        var parts: [String] = []
        var index = 0
        while index < sets.count {
            let current = sets[index]
            var count = 1
            while index + count < sets.count,
                  sets[index + count].reps == current.reps,
                  sets[index + count].weightKg == current.weightKg {
                count += 1
            }
            let weight = current.weightKg > 0 ? " × \(NumberText.text(current.weightKg))kg" : ""
            parts.append(count > 1 ? "\(count)×\(current.reps)\(weight)" : "\(current.reps)\(weight)")
            index += count
        }
        return parts.joined(separator: " · ")
    }

    private func cardioRow(_ session: CardioSession) -> some View {
        Button {
            onEdit(.cardio(session))
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Color("TextPrimary"))
                        .lineLimit(1)
                    Text(cardioSummary(session))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color("TextSecondary"))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(session.kcalBurned))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color("TextPrimary"))
                    Text("kcal")
                        .font(.system(size: 10))
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cardioSummary(_ session: CardioSession) -> String {
        var parts = ["\(NumberText.text(session.durationMin)) \(String(localized: "分钟"))"]
        if let distance = session.distanceKm, distance > 0 {
            parts.append("\(NumberText.text(distance)) km")
        }
        if session.kcalSource == .device {
            parts.append(String(localized: "设备读数"))
        }
        return parts.joined(separator: " · ")
    }
}
