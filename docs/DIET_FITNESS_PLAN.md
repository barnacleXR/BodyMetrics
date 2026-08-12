# BodyMetrics × 饮食健身打卡：深度融合实施计划

> **状态：M1–M6 全部实现完毕**（84 个单元测试通过，模拟器实机走查通过）。
> 实现过程中发现并修正的问题记录在文末「实现记录」一节，其中三个是会实际伤到用户的 bug。

## Context

现有 iOS App（SwiftUI + SwiftData，iOS 26.4）只记录体重/体脂率；HTML 原型（`docs/prototype/diet-fitness-log.html`，2522 行）记录饮食宏量与力量/有氧训练。两者都是「本地、无账号、无网络」，且 tab 结构几乎同构。

用户的核心要求：**不是把饮食模块追加到体重 App 旁边，而是深度融合**。

因此本计划的立足点是：**体重是结果，饮食与训练是输入，两者必须互相校准，形成能量收支闭环**。融合的存在理由是一批「两份数据不在同一个 App 里就做不出来」的能力——自适应 TDEE 校准、体重预测线、目标体重↔热量目标联动。如果做完之后这些能力不存在，那这次就只是并排追加，等于失败。

分支 `feature/diet-fitness-log` 已建并推送；`docs/DIET_FITNESS_PLAN.md`（上一版按领域合并的方案）由本计划取代，M1 时替换。

---

## 一、融合契约：12 条必须成立的事

实现完成的判定标准就是这 12 条全部成立。带 ★ 的是只有融合才可能实现的能力。

| # | 融合点 | 含义 |
|---|---|---|
| F1 | 体重 → TDEE | 删除原型手填的 `profile.weightKg`，TDEE 直接读**最新体重记录**；体重变，基础代谢与推荐目标自动跟着变 |
| F2 ★ | 热量差额 → 预测体重 | 累计净差额 ÷ 7700 kcal/kg 得预测体重曲线，与实测曲线画在同一张图上 |
| F3 ★ | 实测 vs 预测 → 自适应 TDEE | 用近 28 天实测体重变化反推真实代谢，与公式值对比并可一键采纳 |
| F4 ★ | 目标体重 + 速度 → 热量目标 | 用户只填「目标体重」与「每周期望变化」，系统推出每日热量与宏量目标，并给出**预计达成日期** |
| F5 | 单一日视图 | 记录页 = 这一天的全部（体重 + 饮食 + 训练 + 备注），日期导航对全部领域同时生效 |
| F6 | 单一日历 | 一个日期格三态：体重数字 + 热量达标点 + 训练标记 |
| F7 | 单一趋势 | 体重曲线 / 热量柱 / 训练容量共用一条时间轴 |
| F8 | 单一档案 | `UserProfile` 承载全部身体与偏好数据，身高、目标体重复用现有字段 |
| F9 | 单一导出 | AI 分析 JSON 同时含体重序列与能量平衡结论；备份覆盖全部实体 |
| F10 | 单一提醒 | `Reminder` 加类型（晨间称重/三餐/训练后），文案对应 |
| F11 | 单一锁 | 现有生物识别锁保护范围自然扩大到饮食训练数据，无需改代码 |
| F12 | 单一 streak | 连续打卡 = 当天有**任意**记录，不分两套 |

---

## 二、架构决策

### 2.1 Tab 保持 4 个，按领域合并

`记录 / 日历 / 趋势 / 设置` 不变，不加第 5 个 tab。加 tab 就是承认没融合。

### 2.2 存储：`MetricEntry` 不动，`DayLog` 平行新增

**决策：体重不搬进 `DayLog`。**

`MetricEntry`（[Models/MetricEntry.swift](../BodyMetrics/Models/MetricEntry.swift)）是追加式、带精确时间戳、允许同日多条的模型，现有日历编辑逻辑（[LogSheetView.swift:150](../BodyMetrics/Views/LogSheetView.swift)）依赖「当日最新一条」语义。硬塞进 `DayLog` 会破坏该语义并带来真实的迁移风险。

`DayLog` 用 `dayStart`（`Calendar.startOfDay` 归一）作唯一键，与体重**按日期在计算层关联**，不建 SwiftData 关系。

**融合发生在计算层与视图层，而不是靠强行合并存储。** 这样迁移是纯新增（零风险），两边语义各自完整，而用户看到的仍是一个统一的产品。

### 2.3 计算层分三块

| 文件 | 职责 |
|---|---|
| `Services/StatsCalculator.swift`（扩展） | 体重域，已有；新增体重移动平均 |
| `Services/NutritionCalculator.swift`（新） | `core.js` 的营养/训练纯函数直译 |
| `Services/EnergyBalanceService.swift`（新） | **融合核心**：F2/F3/F4 三件事 |

---

## 三、数据模型

新增 `Models/` 下 10 个 `@Model`。全部属性带默认值（与现有 `MetricEntry`/`UserProfile` 写法一致，保证 SwiftData 轻量迁移与 CloudKit 兼容）。

```
DayLog          dayStart(唯一, startOfDay), note, meals/strength/cardio (cascade)
Meal            type: MealType(breakfast/lunch/dinner/snack), items (cascade)
FoodItem        name, basis(.per100g/.perServing), servingLabel, amount, kcal, p, f, c
StrengthWorkout name, sets (cascade), kcalBurned, kcalSource(.manual/.device)
StrengthSet     reps, weightKg, isWarmup
CardioSession   name, durationMin, distanceKm?, kcalBurned, kcalSource
NutritionTarget effectiveFrom, kcal, proteinG, fatG, carbG     ← 版本化
FoodPreset      name, basis, servingLabel, kcal, p, f, c, usageCount, lastUsedAt
CustomExercise  zh, kind(.strength/.cardio), group
AIReport        createdAt, rangeFrom, rangeTo, promptUsed, responseText, payloadSnapshot: Data
```

`UserProfile` 扩展（[Models/UserProfile.swift](../BodyMetrics/Models/UserProfile.swift)，`goalWeight`/`heightCm` 复用现有字段）：

```swift
var sex: Sex = .male
var birthYear: Int = 0                        // 0 = 未设置；不编造默认值，假数据会让 TDEE 静默失真
var activityLevel: ActivityLevel = .sedentary
var weeklyRateKg: Double = -0.5               // F4：每周期望变化，负为减重
var addBurnedToBudget: Bool = false           // 活动系数已含日常活动，默认不回补
var useAdaptiveTDEE: Bool = false             // F3：是否采纳自适应值
var themePreference: ThemePreference = .system
var hiddenBuiltinExerciseIDs: [String] = []
```

`Reminder` 扩展：`var kind: ReminderKind = .weighIn`（weighIn / meal / postWorkout），仅影响通知文案。

内置动作库（36 力量 + 12 有氧）落 `Services/ExerciseCatalog.swift` 静态常量。

**四条硬约束**（原型已踩过的坑，实现时不得违反）：
1. `FoodItem` 存**快照值**，不存对 `FoodPreset` 的引用——改食物库不得追溯修改历史。
2. `NutritionTarget` 取值 = 所有 `effectiveFrom <= 该日` 中最晚一条——改目标不得重写历史达标率。
3. 日期一律 `Calendar.startOfDay` 本地归一，禁止 UTC 转换。
4. 动作名以字符串存在记录里，重命名必须同步改写历史，否则统计里同一动作裂成两条。

---

## 四、计算层公式（融合核心）

### NutritionCalculator（直译 `core.js`）

Mifflin-St Jeor BMR、`tdee = bmr × activityFactor`、`scaleFood`、Epley `e1rm = w × (1 + reps/30)`、`setVolume`（跳过热身组）、`dayTotals`、`remaining`、`draftTotals`、`streak`。

签名改动（F1）：`tdee(profile:currentWeightKg:)` —— 体重是入参，从 `MetricEntry` 取最新值，`UserProfile` 不再存体重。

### EnergyBalanceService（新写）

```
常量 KCAL_PER_KG = 7700

F2 预测体重
  W(d) = W₀ + Σ(intake_i − tdee_i) / 7700
  仅对有完整摄入记录的日累计；缺记录的日跳过并在图上断开，不当作 0 摄入

F4 目标热量
  dailyDelta = weeklyRateKg × 7700 / 7
  targetKcal = tdee + dailyDelta                        (减重时 delta 为负)
  安全钳制：targetKcal 不低于 bmr，触发时钳制并告警
  宏量：P = 1.6 g/kg（实测体重）, F = 25% 热量, C 补足
  achievableWeeklyRate = 钳制后真正生效的差额倒推出的速度
  预计达成日期 = 今天 + (目标体重 − 当前体重) / achievableWeeklyRate 周

F3 自适应 TDEE（近 28 天窗口）
  adaptiveTDEE = 日均摄入 − 每日体重变化 × 7700        ← 用速率，不用总量
  每日体重变化 = (末端 7 日均值 − 首端 7 日均值) / 两端质心的实际间距
  准入门槛（任一不满足则返回「数据不足」，不返回数字）：
    · 窗口内摄入记录完整天数 ≥ 20
    · 首尾各 7 日窗口内各至少 3 次称重
    · 两端质心间距 ≥ 7 天
  合理性钳制：结果落在 公式TDEE 的 0.6×–1.6× 之外时标为不可信
  绝不自动生效——只展示对比，用户显式采纳后写入 useAdaptiveTDEE
```

**两处在 M1 实现时修正的算法（不要退回原写法）**：

1. **F3 必须用速率而非总量。** 首尾各 7 日的均值代表的是各自窗口的**质心时刻**（约相距 21 天），不是整个 28 天。拿 28 天的摄入总量去配 21 天跨度的体重变化，会系统性地把 TDEE 算偏约 25%。两边都化成「每天多少」再相减才无偏。质心按实际称重日期计算，称重不规律时也不失准。
2. **F4 的预计达成日期必须用 `achievableWeeklyRateKg`。** 久坐者的 TDEE 与 BMR 相差有限（如 70 kg/175 cm/30 岁男性：1979 vs 1649，只有 330 kcal 空间），设 −0.5 kg/周 会触发 BMR 钳制。此时若仍按用户设定的 −0.5 报达成日期，就是给一个永远兑现不了的承诺。钳制不是 bug，它在说「光靠吃少达不到这个速度」，界面要照实说。

**F3 的主要失效模式必须防住**：漏记几天饮食会让 `Σ intake` 偏低，从而把 TDEE 反推得虚低，用户照此加大缺口 → 越吃越少。上面的准入门槛与钳制就是为此，实现时不得放宽。

### StatsCalculator 扩展

新增 `trailingAverage(days:endingOn:in:)` 体重移动平均（复用现有私有 `dailyMean` 的按日取最新逻辑，提为可复用函数），供 F2/F3 使用。

---

## 五、页面改造

### 记录页（[RecordView.swift](../BodyMetrics/Views/RecordView.swift)，改动最大）

```
页头     ‹  今日 / 周一 8月12日  ›        [日历]     ← 日期导航新增，对全领域生效
Hero     ┌──────────────┬──────────────┐
         │ 体重 62.4 kg │ 剩余 480 kcal│              ← 左右分栏，一眼看到输入与结果
         │ ↓0.2 较昨日  │ 已摄入 1620  │
         ├──────────────┴──────────────┤
         │ P ▓▓▓░ 82/120  F ▓▓ 40/60  C ▓▓▓ 150/200 │
         └─────────────────────────────┘
进度区   目标体重 58.0 kg  距 4.4 kg   [环 42%]
         预计 11月3日达成 · 按 −0.5 kg/周          ← F4，两个领域合成一条结论
试算区   （仅有内容时出现）
当日记录 早餐 / 午餐 / 晚餐 / 加餐 / 力量 / 有氧
备注
底部     [ 记录 ] → 体重 / 饮食 / 力量 / 有氧 四选一
```

- 未设营养目标时，Hero 右半变为「设定每日目标」按钮，**不弹全屏引导拦住老用户**（原型的 `onboarded` 强拦逻辑按此改写）。
- 现有绿色渐变 hero 样式、`iconCircle`、卡片圆角与 colorset（`BrandGreen`/`CardBackground`/`PageBackground`/`HeroGradientStart|End`/`TextPrimary`/`TextSecondary`）全部复用，不新造视觉体系。
- 删除/编辑走「删除 + 撤销 toast」，不用确认弹窗打断；toast 复用 [SettingsView.swift:179](../BodyMetrics/Views/SettingsView.swift) 已有的 overlay 写法，提取成 `Views/Components/ToastOverlay.swift`。

### 日历页（[CalendarView.swift](../BodyMetrics/Views/CalendarView.swift)）

日期格在现有体重数字下加一行状态点：热量达标（±10%）实心 / 偏离 warn 色 / 训练日哑铃点。现有翻月 `simultaneousGesture`、整格可点、`day(for:)` 网格计算全部保留。详情条扩展为可展开的日摘要（热量宏量 + 记录清单 + 备注），「编辑」跳记录页对应日期。

### 趋势页（[TrendView.swift](../BodyMetrics/Views/TrendView.swift)）

指标分段加 `热量 / 训练容量`；体重图叠加 F2 预测线（虚线 `LineMark` + `dash`）；下方加：
- 统计卡 4 格：平均热量 / 平均蛋白 / 热量达标天 / 训练总容量
- **自适应 TDEE 卡（F3）**：`公式 2180 → 实测 2045 kcal（低 6%）`，附「采纳」按钮与数据不足时的说明
- 现有 `insightCard` 升级为融合结论（体重变化 + 摄入达标率一起说）

### 设置页（[SettingsView.swift](../BodyMetrics/Views/SettingsView.swift)）

现有 `groupTitle`/`row`/`roundIcon`/`card()` 组件复用。新增分组：身体档案（性别/出生年/身高/活动强度）、目标（目标体重 + 每周速度 → 实时预览推算出的热量宏量 + 手动覆盖 + 「保存为今天起生效」）、偏好（训练消耗回补 / 主题）、资料库（常用食物 / 动作库）、数据（JSON 备份导入导出 / 清空）。CSV 导出扩展为体重 + 饮食两份。

### 新增页面

`Views/Nutrition/` 下：`FoodFormView`、`StrengthFormView`、`CardioFormView`、`FoodLibraryView`、`ExerciseLibraryView`、`DraftBoxView`（试算）、`AIExportView`、`NutritionOnboardingView`。

---

## 六、分期实施

每期一个 commit，M1/M2 完成后先在模拟器实跑再往下推。

| 期 | 内容 | 关键文件 | 验证 |
|---|---|---|---|
| **M1** | 单元测试 target（手工改 pbxproj，objectVersion 77 + fileSystemSynchronizedGroup）；10 个 `@Model` + `UserProfile`/`Reminder` 扩展；`ModelContainer` 与全部 `#Preview` 注册新类型；`NutritionCalculator` + `EnergyBalanceService` + `StatsCalculator` 扩展；本计划替换 `docs/DIET_FITNESS_PLAN.md` | `Models/*`, `Services/NutritionCalculator.swift`, `Services/EnergyBalanceService.swift`, `BodyMetricsApp.swift` | `xcodebuild test` 全绿；装旧版再装新版验证迁移不丢数据 |
| **M2** | 记录页融合：日期导航、双栏 Hero、当日记录列表、四选一录入、三个表单、编辑/删除+撤销 | `RecordView.swift`, `Views/Nutrition/*Form*` | 模拟器完整走一遍：记体重→记三餐→记力量→改→删→撤销 |
| **M3** | 试算区、食物库、动作库（含重命名同步改写历史）、录入自动入库 | `DraftBoxView`, `FoodLibraryView`, `ExerciseLibraryView` | 重命名后历史记录同步改名，统计不裂条 |
| **M4** | 目标体系融合：F4 联动、身体档案、偏好、轻量引导；安全钳制与告警 | `SettingsView.swift`, `NutritionOnboardingView` | 改目标体重/速度 → 热量宏量与预计达成日期实时变；低于 BMR 时告警 |
| **M5** | 日历三态与日摘要；趋势页三合一 + F2 预测线 + F3 自适应卡 | `CalendarView.swift`, `TrendView.swift` | 造 30 天数据，核对预测线与自适应 TDEE；再造「漏记 10 天」数据，确认返回"数据不足"而非错误数字 |
| **M6** | AI 导出（含体重序列与能量平衡结论）、AI 存档、JSON 备份导入导出（兼容原型 schema v3）、CSV 扩展、提醒分类、xcstrings 补全、深色模式与 VoiceOver 核查 | `AIExportView`, `Services/BackupService.swift`, `CSVExporter.swift` | 导出 JSON 结构核对；导入原型导出的备份成功；深色/浅色/动态字体三轮走查 |

---

## 七、我替你做的决策

| 决策 | 选择 | 理由 |
|---|---|---|
| Tab 数量 | 保持 4 个 | 加第 5 个 tab 等于承认没融合 |
| 体重存储 | `MetricEntry` 不动，`DayLog` 平行 | 迁移零风险；融合放在计算层，不牺牲现有语义 |
| App 显示名 | **改为「体重管理」→ 待 M6 定，暂不改** | 改名涉及 Info.plist 与 xcstrings，等产品成型再定，不在实现期反复折腾 |
| HealthKit | **不接** | 违背「纯本地、无账号、无网络」核心原则；要接需单开一期并重新评估隐私说明 |
| 食物数据库 | **不接**，沿用手输 + 自建库 | 保持离线零依赖；使用频次排序已能覆盖日常 |
| AI 分析 | 维持「复制 JSON 出去、粘结论回来」 | App 内直连 API 会打破无网络原则 |
| 单位制 | 只做公制 | 原型与现有 App 都是公制，加英制是范围膨胀 |
| 首次引导 | 不全屏强拦，改为 Hero 上的占位入口 | 老用户已有体重数据，不能被引导页挡在门外 |
| 自适应 TDEE | 默认关闭，需用户显式采纳 | 数据不足时给错数字比不给更危险 |

前四条你若想推翻，M1 开始前说一声即可；M4 之后再改 HealthKit 或食物库会返工。

---

## 八、风险

1. **pbxproj 手工加测试 target**：无 `xcodeproj` gem / xcodegen 可用，只能手改。M1 第一步单独 commit，`xcodebuild test` 不通过就整体回退，改为不带测试推进（会显著削弱 F3 的可信度，故优先尝试）。
2. **SwiftData 关系与迁移**：10 个新模型一次引入，`@Relationship` cascade 写错会静默丢数据。M1 必须先建再装旧版数据验证迁移，不能等到 M5。
3. **F3 数据不足时给出错误代谢值**：已用准入门槛 + 钳制 + 默认关闭三重防护，实现时不得放宽阈值。
4. **记录页信息密度**：双栏 Hero + 进度 + 试算 + 四类记录，容易过载。M2 完成后在模拟器上按真实数据量走查，必要时把试算区收进 sheet。
5. **原型数据迁入**：M6 的导入必须严格对齐原型 `schemaVersion: 3` 字段名，不得中途改名。

---

## 九、端到端验证

```bash
# 构建 + 单元测试
xcodebuild -project BodyMetrics.xcodeproj -scheme BodyMetrics \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

模拟器验收脚本（M6 后完整跑一遍）：
1. 全新安装 → 记一条体重 → Hero 右半提示「设定每日目标」→ 设目标体重 57 kg、−0.5 kg/周 → 确认热量/宏量/预计达成日期三项同时出现
2. 记早餐/午餐/力量各一条 → 剩余热量与 P/F/C 条实时递减 → 删一条 → toast 撤销 → 数据回来
3. 翻到昨天补录 → 日历对应格出现体重数字 + 达标点 + 训练点
4. 造 30 天数据 → 趋势页体重图出现预测虚线；自适应 TDEE 卡给出对比值
5. 删掉其中 12 天的饮食记录 → 自适应卡改为「数据不足」而非错误数字
6. 导出 AI JSON → 确认含体重序列与能量平衡字段；导出完整备份 → 清空 → 导入 → 数据完全恢复
7. 深色模式 + 最大动态字体 + VoiceOver 各走一遍主流程

---

## 十、实现记录

### 会实际伤到用户的三个 bug

1. **老用户一开 App 就闪退**（M4 发现）
   SwiftData 的轻量迁移只给旧表加列、**不回填默认值**。老用户 `UserProfile` 那一行的新列是 NULL，而非可选的 Codable 枚举属性一读就 `Could not cast Optional<Any>` 崩溃。M1/M2 没暴露只是因为当时还没有代码去读它。
   **对策**：加在**已存在模型**上的枚举与数组一律用可空原始值存储 + 计算属性兜底（`sexRaw`/`activityLevelRaw`/`themePreferenceRaw`/`hiddenExerciseIDsRaw`/`kindRaw`）。全新模型不受影响，它们每行都是新写入的。见 `MigrationSafetyTests`。

2. **撤销静默失效**（M2 发现，单元测试测不出）
   撤销闭包在 sheet 关闭**之后**才执行，那时 `@Environment(\.modelContext)` 已不再挂在任何视图上，读到的是没接容器的空 context，写入直接进虚空。删除能生效是因为它在视图还活着时跑。
   **对策**：闭包创建时就把 context 捕获成局部常量。服务层测试是通过的，只有上手点才暴露。

3. **常用食物库每记一次堆一条重复项**（M2 发现）
   `#Predicate` 里比较自定义 Codable 枚举会静默失配。
   **对策**：谓词只按字符串字段建，枚举放到 Swift 层过滤。

### 两处算法修正

4. **自适应 TDEE 有约 25% 的系统性偏差**（M1 写测试时发现）
   首尾各 7 日均值的**质心相距约 21 天**而非 28 天，拿 28 天摄入总量去配 21 天跨度的体重变化必然算偏。
   **对策**：改用速率形式（日均摄入 − 每日体重变化 × 7700），质心按实际称重日期计算，称重不规律时也不失准。

5. **预计达成日期会给假承诺**（M1 测试失败暴露）
   久坐 70 kg/175 cm/30 岁男性 TDEE 1979、BMR 1649，只有 330 kcal 空间，设 −0.5 kg/周 必然触发 BMR 钳制。原实现仍按用户设定的速度报日期。
   **对策**：新增 `achievableWeeklyRateKg`，日期按钳制后实际可达成的速度算，界面照实说「靠饮食实际能达到约 −0.3 kg/周，想更快得靠增加活动量，不是再少吃」。

### 一个渲染 bug

6. **单日数据时体重图画成一根竖线**（M5 发现）
   实测线与预测线未声明 `series:`，Charts 把同一天的两个点当成一条线连了起来。
   **对策**：显式区分 series，并在单点时补 `PointMark`。

### 未做

- HealthKit、食物数据库、App 内直连 AI API、英制单位——均按计划第七节的决策**有意不做**，理由见该节。
- 自适应 TDEE 与体重预测线的**满数据实机效果**未在模拟器上验证（需要 28 天真实记录）。相关数学由 `EnergyBalanceServiceTests` 覆盖，含"漏记 13 天时必须拒绝给出代谢值"的用例。
