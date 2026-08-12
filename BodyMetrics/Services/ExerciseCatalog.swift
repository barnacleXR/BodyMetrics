import Foundation

/// 内置动作库(精简自常见训练动作)。用户可隐藏其中任意一条,也可另加自定义动作。
enum ExerciseCatalog {
    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let group: String
    }

    static let cardioGroup = String(localized: "有氧")
    static let customGroup = String(localized: "自定义")

    static let strength: [Entry] = [
        Entry(id: "bench-press", name: String(localized: "卧推"), group: String(localized: "胸")),
        Entry(id: "incline-bench", name: String(localized: "上斜卧推"), group: String(localized: "胸")),
        Entry(id: "db-bench", name: String(localized: "哑铃卧推"), group: String(localized: "胸")),
        Entry(id: "chest-fly", name: String(localized: "飞鸟"), group: String(localized: "胸")),
        Entry(id: "push-up", name: String(localized: "俯卧撑"), group: String(localized: "胸")),
        Entry(id: "dip", name: String(localized: "双杠臂屈伸"), group: String(localized: "胸")),
        Entry(id: "pull-up", name: String(localized: "引体向上"), group: String(localized: "背")),
        Entry(id: "lat-pulldown", name: String(localized: "高位下拉"), group: String(localized: "背")),
        Entry(id: "barbell-row", name: String(localized: "杠铃划船"), group: String(localized: "背")),
        Entry(id: "db-row", name: String(localized: "单臂哑铃划船"), group: String(localized: "背")),
        Entry(id: "seated-row", name: String(localized: "坐姿划船"), group: String(localized: "背")),
        Entry(id: "deadlift", name: String(localized: "硬拉"), group: String(localized: "背")),
        Entry(id: "romanian-dl", name: String(localized: "罗马尼亚硬拉"), group: String(localized: "腿")),
        Entry(id: "squat", name: String(localized: "深蹲"), group: String(localized: "腿")),
        Entry(id: "front-squat", name: String(localized: "前蹲"), group: String(localized: "腿")),
        Entry(id: "leg-press", name: String(localized: "腿举"), group: String(localized: "腿")),
        Entry(id: "lunge", name: String(localized: "弓步蹲"), group: String(localized: "腿")),
        Entry(id: "leg-extension", name: String(localized: "腿屈伸"), group: String(localized: "腿")),
        Entry(id: "leg-curl", name: String(localized: "腿弯举"), group: String(localized: "腿")),
        Entry(id: "calf-raise", name: String(localized: "提踵"), group: String(localized: "腿")),
        Entry(id: "hip-thrust", name: String(localized: "臀推"), group: String(localized: "腿")),
        Entry(id: "ohp", name: String(localized: "站姿推举"), group: String(localized: "肩")),
        Entry(id: "db-shoulder-press", name: String(localized: "哑铃肩推"), group: String(localized: "肩")),
        Entry(id: "lateral-raise", name: String(localized: "侧平举"), group: String(localized: "肩")),
        Entry(id: "front-raise", name: String(localized: "前平举"), group: String(localized: "肩")),
        Entry(id: "rear-delt-fly", name: String(localized: "反向飞鸟"), group: String(localized: "肩")),
        Entry(id: "shrug", name: String(localized: "耸肩"), group: String(localized: "肩")),
        Entry(id: "barbell-curl", name: String(localized: "杠铃弯举"), group: String(localized: "手臂")),
        Entry(id: "db-curl", name: String(localized: "哑铃弯举"), group: String(localized: "手臂")),
        Entry(id: "hammer-curl", name: String(localized: "锤式弯举"), group: String(localized: "手臂")),
        Entry(id: "tricep-pushdown", name: String(localized: "三头下压"), group: String(localized: "手臂")),
        Entry(id: "skullcrusher", name: String(localized: "仰卧臂屈伸"), group: String(localized: "手臂")),
        Entry(id: "plank", name: String(localized: "平板支撑"), group: String(localized: "核心")),
        Entry(id: "crunch", name: String(localized: "卷腹"), group: String(localized: "核心")),
        Entry(id: "hanging-leg-raise", name: String(localized: "悬垂举腿"), group: String(localized: "核心")),
        Entry(id: "cable-woodchop", name: String(localized: "绳索转体"), group: String(localized: "核心")),
    ]

    static let cardio: [Entry] = [
        Entry(id: "run-outdoor", name: String(localized: "跑步(户外)"), group: cardioGroup),
        Entry(id: "run-treadmill", name: String(localized: "跑步机"), group: cardioGroup),
        Entry(id: "walk", name: String(localized: "快走"), group: cardioGroup),
        Entry(id: "cycling", name: String(localized: "骑行"), group: cardioGroup),
        Entry(id: "stationary-bike", name: String(localized: "动感单车"), group: cardioGroup),
        Entry(id: "elliptical", name: String(localized: "椭圆机"), group: cardioGroup),
        Entry(id: "rowing", name: String(localized: "划船机"), group: cardioGroup),
        Entry(id: "stair-climber", name: String(localized: "爬楼机"), group: cardioGroup),
        Entry(id: "swimming", name: String(localized: "游泳"), group: cardioGroup),
        Entry(id: "jump-rope", name: String(localized: "跳绳"), group: cardioGroup),
        Entry(id: "hiit", name: "HIIT", group: cardioGroup),
        Entry(id: "other-cardio", name: String(localized: "其他有氧"), group: cardioGroup),
    ]

    static func builtin(for kind: ExerciseKind) -> [Entry] {
        kind == .cardio ? cardio : strength
    }

    /// 力量动作的部位顺序(展示用)
    static let strengthGroupOrder: [String] = [
        String(localized: "胸"), String(localized: "背"), String(localized: "腿"),
        String(localized: "肩"), String(localized: "手臂"), String(localized: "核心"),
    ]
}
