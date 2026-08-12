import Foundation

/// 表单提交出来的、已校验的记录内容。
///
/// 用值类型而非直接改 `@Model` 的原因有二:表单可以随意编辑而不污染数据库;
/// 删除时留一份快照就能实现撤销,不必依赖 undoManager。
struct FoodDraft: Equatable {
    var name: String = ""
    var basis: FoodBasis = .per100g
    var servingLabel: String = ""
    var amount: Double = 0
    var kcal: Double = 0
    var proteinG: Double = 0
    var fatG: Double = 0
    var carbG: Double = 0

    init(
        name: String = "", basis: FoodBasis = .per100g, servingLabel: String = "",
        amount: Double = 0, kcal: Double = 0, proteinG: Double = 0, fatG: Double = 0, carbG: Double = 0
    ) {
        self.name = name
        self.basis = basis
        self.servingLabel = servingLabel
        self.amount = amount
        self.kcal = kcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbG = carbG
    }

    init(from item: FoodItem) {
        self.init(
            name: item.name, basis: item.basis, servingLabel: item.servingLabel,
            amount: item.amount, kcal: item.kcal, proteinG: item.proteinG,
            fatG: item.fatG, carbG: item.carbG
        )
    }

    /// 本条实际贡献的营养(份量已换算)
    var macros: MacroTotals {
        NutritionCalculator.scaled(
            basis: basis, amount: amount,
            kcal: kcal, proteinG: proteinG, fatG: fatG, carbG: carbG
        )
    }

    func makeItem() -> FoodItem {
        FoodItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            basis: basis, servingLabel: servingLabel, amount: amount,
            kcal: kcal, proteinG: proteinG, fatG: fatG, carbG: carbG
        )
    }

    func apply(to item: FoodItem) {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.basis = basis
        item.servingLabel = servingLabel
        item.amount = amount
        item.kcal = kcal
        item.proteinG = proteinG
        item.fatG = fatG
        item.carbG = carbG
    }
}

struct SetDraft: Equatable, Identifiable {
    var id = UUID()
    var reps: Int = 0
    var weightKg: Double = 0
    var isWarmup: Bool = false
}

struct StrengthDraft: Equatable {
    var name: String = ""
    var sets: [SetDraft] = []
    var kcalBurned: Double = 0
    var kcalSource: KcalSource = .manual

    init(name: String = "", sets: [SetDraft] = [], kcalBurned: Double = 0, kcalSource: KcalSource = .manual) {
        self.name = name
        self.sets = sets
        self.kcalBurned = kcalBurned
        self.kcalSource = kcalSource
    }

    init(from workout: StrengthWorkout) {
        self.init(
            name: workout.name,
            sets: workout.orderedSets.map {
                SetDraft(reps: $0.reps, weightKg: $0.weightKg, isWarmup: $0.isWarmup)
            },
            kcalBurned: workout.kcalBurned,
            kcalSource: workout.kcalSource
        )
    }

    /// 容量与 e1RM 都跳过热身组
    var volumeKg: Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + Double($1.reps) * $1.weightKg }
    }

    var bestE1RM: Double {
        sets.filter { !$0.isWarmup }
            .map { NutritionCalculator.e1rm(weightKg: $0.weightKg, reps: $0.reps) }
            .max() ?? 0
    }

    func makeWorkout(sortIndex: Int) -> StrengthWorkout {
        let workout = StrengthWorkout(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kcalBurned: kcalBurned, kcalSource: kcalSource, sortIndex: sortIndex
        )
        workout.sets = sets.enumerated().map { index, set in
            StrengthSet(reps: set.reps, weightKg: set.weightKg, isWarmup: set.isWarmup, sortIndex: index)
        }
        return workout
    }

    func apply(to workout: StrengthWorkout) {
        workout.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.kcalBurned = kcalBurned
        workout.kcalSource = kcalSource
        workout.sets = sets.enumerated().map { index, set in
            StrengthSet(reps: set.reps, weightKg: set.weightKg, isWarmup: set.isWarmup, sortIndex: index)
        }
    }
}

struct CardioDraft: Equatable {
    var name: String = ""
    var durationMin: Double = 0
    var distanceKm: Double? = nil
    var kcalBurned: Double = 0
    var kcalSource: KcalSource = .manual

    init(
        name: String = "", durationMin: Double = 0, distanceKm: Double? = nil,
        kcalBurned: Double = 0, kcalSource: KcalSource = .manual
    ) {
        self.name = name
        self.durationMin = durationMin
        self.distanceKm = distanceKm
        self.kcalBurned = kcalBurned
        self.kcalSource = kcalSource
    }

    init(from session: CardioSession) {
        self.init(
            name: session.name, durationMin: session.durationMin, distanceKm: session.distanceKm,
            kcalBurned: session.kcalBurned, kcalSource: session.kcalSource
        )
    }

    func makeSession(sortIndex: Int) -> CardioSession {
        CardioSession(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            durationMin: durationMin, distanceKm: distanceKm,
            kcalBurned: kcalBurned, kcalSource: kcalSource, sortIndex: sortIndex
        )
    }

    func apply(to session: CardioSession) {
        session.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.durationMin = durationMin
        session.distanceKm = distanceKm
        session.kcalBurned = kcalBurned
        session.kcalSource = kcalSource
    }
}
