# 饮食健身打卡 → BodyMetrics 集成计划

> 分支：`feature/diet-fitness-log`
> 原型：[`docs/prototype/diet-fitness-log.html`](prototype/diet-fitness-log.html)（2522 行，`core.js` 纯逻辑层 + React UI 层）
> 目标：把原型的**全部功能**并入现有 iOS App（SwiftUI + SwiftData，iOS 26.4），不是新建一个 App，而是让「体重」与「饮食/训练」成为同一份数据。

---

## 1. 现状盘点

| | 现有 iOS App | HTML 原型 |
|---|---|---|
| 领域 | 体重 / 体脂率 | 饮食（宏量）/ 力量 / 有氧 |
| 存储 | SwiftData（`MetricEntry` / `UserProfile` / `Reminder`） | localStorage 单个 JSON，`schemaVersion: 3` |
| Tab | 记录 / 日历 / 趋势 / 设置 | 今日 / 历史 / 统计 / 设置 |
| 计算 | `StatsCalculator`（较昨日、周变化、目标进度、BMI） | `core.js`（BMR/TDEE、宏量目标、e1RM、容量、streak） |
| 导出 | CSV（`CSVExporter`） | AI 分析 JSON + 完整备份 JSON |
| 其他 | 提醒通知、生物识别锁、本地化 xcstrings | 主题切换、Toast 撤销、试算购物车 |

两边的 tab 结构**几乎同构**，这是最大的整合红利：不需要加第五个 tab。

工程侧事实：`BodyMetrics.xcodeproj` 使用 file-system-synchronized group，新增 `.swift` 文件放进目录即自动入编译，无需改 pbxproj。

---

## 2. 信息架构决策

**推荐方案：保持 4 个 tab，按「领域」而非「来源」合并。**

| Tab | 现有内容 | 并入内容 |
|---|---|---|
| **记录** | 今日体重 hero、目标进度、最近记录 | 日期导航（前/后一天、回到今天）、剩余热量 hero + P/F/C 进度条、试算区、当日饮食/力量/有氧记录、备注、统一的「记录」按钮（体重/饮食/力量/有氧四选一） |
| **日历** | 月视图 + 当日体重详情条 | 日期格双状态点（有体重记录 / 热量达标·偏离）、日详情 sheet 增加当日热量宏量摘要与记录清单、连续打卡天数 |
| **趋势** | 体重折线图、区间切换、统计卡 | 每日热量柱状图（达标实心 + 目标虚线）、平均热量/平均蛋白/达标天数/训练总容量、导出给 AI 分析、AI 分析存档 |
| **设置** | 目标体重、身高、提醒、生物锁、CSV 导出 | 个人档案（性别/出生年/活动强度）、每日营养目标（TDEE 推荐值 + 生效日期版本化）、训练消耗回补开关、主题、常用食物库、动作库、JSON 备份导入导出、清空数据 |

**备选方案**（若你希望两个领域完全解耦）：加第 5 个 tab「饮食」。代价是底部 5 个 tab 拥挤，且「今天吃了什么」和「今天多重」被割裂在两页，日历会出现两套。**不推荐**，但决定权在你。

一个关键收敛点：原型的 `profile.weightKg` 是手填的静态值，只为算 BMR。并入后应直接取**最新一条体重记录**，TDEE 随体重自动更新——这是两个 App 合并后才有的能力，也是本次整合的核心价值。

---

## 3. 数据模型（SwiftData）

新增 8 个 `@Model`，全部是**新增类型**，对现有 `MetricEntry` 无破坏性改动，SwiftData 轻量迁移即可完成。

```
Models/
  DayLog.swift          // 一天的容器：date(唯一, startOfDay)、note、关系
  Meal.swift            // type: MealType(早/午/晚/加餐)、items
  FoodItem.swift        // name, basis(.per100g/.perServing), servingLabel, amount, kcal, p, f, c
  StrengthWorkout.swift // name, sets, kcalBurned, kcalSource(.manual/.device)
  StrengthSet.swift     // reps, weightKg, isWarmup
  CardioSession.swift   // name, durationMin, distanceKm?, kcalBurned, kcalSource
  NutritionTarget.swift // effectiveFrom, kcal, proteinG, fatG, carbG  ← 版本化，改目标不影响历史
  FoodPreset.swift      // 常用食物库：+ usageCount, lastUsedAt
  CustomExercise.swift  // 自定义动作：zh, kind(.strength/.cardio), group
  AIReport.swift        // createdAt, rangeFrom/To, promptUsed, responseText, payloadSnapshot(Data)
```

`UserProfile` 扩展字段（均带默认值，保证迁移安全）：

```swift
var sex: Sex = .male                       // 用于 Mifflin-St Jeor
var birthYear: Int? = nil                  // 不编造默认值：假数据会让 TDEE 静默失真
var activityLevel: ActivityLevel = .sedentary
var addBurnedToBudget: Bool = false        // 活动系数已含日常活动，默认不回补
var themePreference: ThemePreference = .system
var hiddenBuiltinExerciseIDs: [String] = []
var hasOnboardedNutrition: Bool = false
```

设计要点（沿用原型里已经踩过的坑）：

- **`FoodItem` 存快照值，不存引用**。改食物库只影响以后录入的默认值，历史记录不被追溯修改。
- **`NutritionTarget` 用 `effectiveFrom` 列表**，取某日目标 = 所有 `effectiveFrom <= 该日` 中最晚的一条。改目标绝不能重写历史达标率。
- **`DayLog.date` 用 `Calendar.startOfDay` 归一**，禁止用 UTC 转换（原型专门避开了 `toISOString`）。
- **动作名以字符串存在记录里**，所以重命名必须同步改写历史记录，否则统计里同一动作会裂成两条。
- **`kcalSource`** 必须保留：device 来源误差可达 ±25%，导出给 AI 时要标注，不能当精确值参与能量平衡。

---

## 4. 计算层：`core.js` → `NutritionCalculator.swift`

原型的 `core.js` 是纯函数、零 DOM 依赖，**可以一比一直译成 Swift enum 静态方法**，且天然可单元测试。与现有 `StatsCalculator` 并列，不混在一起。

| core.js | Swift |
|---|---|
| `bmr(sex, w, h, age)` | `bmr(sex:weightKg:heightCm:age:)` Mifflin-St Jeor |
| `tdee(profile)` | `tdee(profile:latestWeight:)` ← 改为取最新体重记录 |
| `suggestTargets` | `suggestedTargets(kcal:weightKg:)` P 1.6 g/kg、F 25% 热量、C 补足 |
| `targetForDate` | `target(on:in:)` |
| `scaleFood` | `FoodItem.scaled` 计算属性 |
| `e1rm` / `setVolume` / `bestE1rm` | Epley 公式；容量跳过热身组 |
| `dayTotals` | `totals(for: DayLog) -> DayTotals` |
| `remaining` / `draftTotals` | `remaining(totals:target:addBurned:draft:)` |
| `streak` | `streak(in:)` 今日无记录时从昨天起算 |
| `exportPayload` | `AIExportBuilder.payload(range:prompt:)` → `Encodable` |

内置动作库（36 个力量 + 12 个有氧）作为 Swift 静态常量落在 `Resources/ExerciseCatalog.swift`，中文名进 xcstrings。

---

## 5. 页面与组件映射

| HTML | SwiftUI |
|---|---|
| `Sheet`（堆栈、Esc 只关顶层） | `.sheet` 原生堆叠 + `.presentationDetents`，堆栈语义系统自带 |
| `Seg` | `Picker(.segmented)` |
| `NumInput`（text + inputMode，避开滚轮改值） | `TextField` + `.keyboardType(.decimalPad)` + keyboard toolbar「收起」 |
| `Switch` | `Toggle` |
| Toast + 撤销 | 自建 `ToastOverlay`（`.overlay` + `.transition`），撤销回滚整份快照；带撤销停留 6 s，普通 2.2 s |
| `confirm()` 删除 | 破坏性操作用 `.alert`；**普通删除一律走「删除 + 撤销 toast」**，不打断操作流 |
| `Hero` + `MacroBar` | 复用现有绿色渐变卡片样式（`HeroGradientStart/End` colorset），P/F/C 用 `Gauge` 或自绘 `Capsule` |
| `spark` 柱状图 | Swift Charts `BarMark` + `RuleMark`（目标虚线） |
| 月历 `cal` | 复用现有 `CalendarView` 网格，日期格加第二个状态点 |
| `downloadFile` | `ShareLink` / `.fileExporter` |
| `copyText` | `UIPasteboard.general.string` |
| 导入 `<input type=file>` | `.fileImporter` |
| `data-theme` 切换 | `.preferredColorScheme`，写进 `UserProfile.themePreference` |
| 跨午夜校正、方向键 | `scenePhase` 回前台校正保留；方向键换成日期格滑动手势（现有 `CalendarView` 已有该模式） |

---

## 6. 功能核对表（原型全量，逐条落地）

**记录（今日）**
- [ ] 日期导航：前一天 / 后一天（未来禁用）/ 回到今天
- [ ] 剩余额度 hero：预算、已摄入、剩余大数字、P/F/C 三条进度条、超标变色
- [ ] 试算区（购物车）：加入 / 移除 / 清空 / 一键记入；切换日期自动清空
- [ ] 训练消耗行 + 回补状态说明
- [ ] 当日记录列表：按餐次分组、力量（组数/容量/e1RM）、有氧（时长/距离/消耗）
- [ ] 编辑任意条目；删除 + 撤销
- [ ] 食物条目可改餐次（从原餐摘除后重新归位，空餐次自动清理）
- [ ] 当日备注
- [ ] 记录 sheet：饮食 / 力量 / 有氧 分段
- [ ] 食物表单：预设搜索带出、每 100 g / 每份 切换、份量、四项宏量、加入试算
- [ ] 力量表单：动作选择、多组 reps/重量/热身标记、e1RM 实时显示、消耗 + 来源
- [ ] 有氧表单：动作、时长、距离、消耗 + 来源
- [ ] 录入新动作名自动入自定义库
- [ ] 录入食物自动 upsert 到常用食物库并累加使用次数

**日历（历史）**
- [ ] 月视图 + 状态点：热量达标（±10%）/ 有记录但偏离 / 空
- [ ] 连续打卡天数
- [ ] 日详情：热量宏量摘要 + 记录清单 + 备注 + 跳转补录

**趋势（统计）**
- [ ] 7 / 30 / 90 天切换
- [ ] 平均热量、平均蛋白、热量达标天数、训练总容量
- [ ] 每日热量柱状图（达标实心 + 目标虚线）
- [ ] 导出给 AI：范围（当天/7/30/全部）、可编辑提示词、数据量提示、空范围警告
- [ ] 复制 JSON / 分享 JSON 文件
- [ ] AI 分析存档：粘贴回复 + 数据快照，可删除、可回看

**设置**
- [ ] 个人档案：性别、出生年、身高、活动强度（体重改为读最新记录）
- [ ] 每日目标：TDEE 估算显示、套用推荐值、手动覆盖、「保存为今天起生效」
- [ ] 训练消耗回补开关（含双重计算说明）
- [ ] 主题：跟随系统 / 浅色 / 深色
- [ ] 常用食物库：搜索、按最常用/最近用/名称排序、增删改
- [ ] 动作库：力量/有氧切换、搜索、按部位分组、隐藏内置、自定义增删、重命名（同步改写历史）
- [ ] 完整备份导出 / 导入（兼容 AI 分析包：只含汇总时仅恢复日期与备注）
- [ ] 清空全部数据（二次确认）
- [ ] 首次引导 Onboarding

**保留不动**：提醒通知、生物识别锁、体重 CSV 导出、BMI。

---

## 7. 实施阶段

| 阶段 | 内容 | 产出 |
|---|---|---|
| **M0** | 分支 + 计划 + 原型归档 | ✅ 本文档 |
| **M1** | 数据模型 + 迁移 + `NutritionCalculator` + 单元测试 | 无 UI，可编译，计算全部有测试覆盖 |
| **M2** | 记录 tab：hero、当日列表、三个录入表单、编辑删除撤销 | 核心闭环可用 |
| **M3** | 试算区 + 食物库 / 动作库两个资料库页 | 录入效率完整 |
| **M4** | 设置：档案、目标版本化、偏好、Onboarding | 目标体系闭环 |
| **M5** | 日历状态点 + 日详情、趋势图表与统计卡 | 回看闭环 |
| **M6** | AI 导出 / 存档、JSON 备份导入导出、本地化补全、无障碍与深色模式核查 | 交付 |

每阶段独立 commit，M1/M2 之后先在模拟器跑一遍再往下推。

---

## 8. 风险与需要你拍板的点

1. **Tab 方案**：推荐「4 tab 按领域合并」，备选「加第 5 个饮食 tab」。这个决定影响 M2 之后的全部 UI 结构，建议先定。
2. **App 定位与命名**：并入后它不再只是「体重管理」，显示名是否要改？（改名涉及 `INFOPLIST_KEY_CFBundleDisplayName` 与 xcstrings）
3. **HealthKit**：原型没有，但 iOS 上「有氧消耗」「体重」都可以从 Apple 健康读写，能省掉大量手输。本计划**默认不含 HealthKit**（保持「纯本地、无账号、无网络」原则），若要做需单开一期。
4. **食物营养数据源**：原型完全靠手输 + 自建库，没有食物数据库。保持现状（离线、零依赖），还是后续接一个本地食物库？本计划按现状办。
5. **数据迁移**：如果你在浏览器里已经用原型记了数据，M6 的「导入备份」可以直接吃原型导出的 JSON——这条通道要在实现时严格按 `schemaVersion 3` 的字段名对齐，别改字段名。
6. **AI 分析目前是「复制 JSON 出去、粘贴结论回来」的手动流程**，与 App「无网络」原则一致。若要改成 App 内直接调 API，会打破该原则，需要你明确同意。
