# 用户向界面第一轮 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改物理口径、不重做 3D 的前提下，把现有四页 + 检查器改成用户能读懂的决策界面：默认只看方案名、温度图、座位冷热、达标座位、一天用电/费用；变量名与求解术语永不出现在未折叠区域。

**Architecture:** 在 `SimuCore` 增加纯字符串呈现层 `UserFacingCopy`（Foundation-only，无 SwiftUI）。视图只消费这层的中文标签；JSON 字段名、`q_cool_w`、`inputHash`、`RunState.rawValue` 仍是内部契约。检查器保持总表，用 `DisclosureGroup` 分「房间 / 使用 / 空调」与折叠区。提交计算从检查器默认区挪到「用电与舒适」。视口只改图例、空状态和座位可读名。RealityKit 3D 按 ADR-016，本轮不做。

**Tech Stack:** Swift 6、SwiftUI（macOS 14 / iOS 17）、Swift Testing、现有 `Scripts/check.sh test|mac|ios`。不新增 UI 测试 target，不新增依赖。

## Global Constraints

- 底座是当前 `dev`（P5 已闭环）。参考 `development` 的说法与折叠，不回退气流场、座位达标、代表日电费。
- 缺数显示「还没有」或「不可评价」，不填 0；一天费用不乘 365；口径不同不排序；质量未通过不涂有效温度；达标座位不叫实测满意率。
- 默认屏禁止：`L1` `L2` `z0` `s0` `q_cool_w` `p_elec_w` `inputHash` `PMV` `PPD` `mrtC` `clo` `met` `JSONL` `stale` `EnergyPlus` `OpenFOAM` `worker` `buoyantBoussinesqSimpleFoam` `xMin` 以及完整 UUID。
- 本轮不做：点选联动、拖拽摆放、补画门/家具、RealityKit 3D、复制方案向导、改 schema / 求解器 / 哈希规则。
- 3D 留给第一轮完成后按 ADR-016 另开工作包。
- 共享 JSON 字段名不改。呈现层只改用户看见的字。
- App schemes 无 UI 测试 target；呈现层用 SwiftPM 单测锁文案。

---

## 已锁定的产品决定

| 项 | 决定 |
|---|---|
| 视口 | A：只做读得懂（图例、空状态、座位人话名）。不画门/家具，不点选。 |
| 检查器 | A：总表加折叠。默认展开房间 / 使用 / 空调。 |
| 提交计算 | 放到「用电与舒适」页，不放在检查器默认区。 |
| 3D | 第一轮完成后再做（ADR-016）。 |

---

## 文件职责

| 文件 | 职责 |
|---|---|
| Create: `Packages/SimuKit/Sources/SimuCore/UserFacingCopy.swift` | 路径、墙面、指标、状态、座位/开口名称、禁止词表 |
| Create: `Packages/SimuKit/Tests/SimuCoreTests/UserFacingCopyTests.swift` | 锁映射与「默认文案不含禁止词」 |
| Modify: `Packages/SimuKit/Sources/SimuCore/SeatFeasibility.swift` | 对比行标签与覆盖文案（取值逻辑不动） |
| Modify: `Packages/SimuKit/Sources/SimuCore/Recommendation.swift` | 建议卡标题/摘要改人话（kind 与 citedRunIDs 不动） |
| Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift` | 导航标题、引擎/任务/导出用户句 |
| Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift` | 四页默认信息与 `DisclosureGroup` |
| Modify: `Packages/SimuKit/Sources/SimuWorkspace/RoomEditorForm.swift` | 三块默认 + 折叠；坐标人话；提交按钮迁出 |
| Modify: `Packages/SimuKit/Sources/SimuVisualization/SlicePalette.swift` | 图例含「坐姿高度 · 蓝凉红热」 |
| Modify: `Packages/SimuKit/Sources/SimuVisualization/SimulationViewport.swift` | 空状态不再写「引擎尚未接入」 |
| Modify: `Packages/SimuKit/Sources/SimuVisualization/RoomScene.swift` | 座位/开口显示名 |
| Modify: `Packages/SimuKit/Sources/SimuVisualization/RoomWireframeView.swift` | 图例与 VoiceOver 用显示名 |
| Modify: `Packages/SimuKit/Sources/SimuReporting/EvidencePDFAssembler.swift` | 正文人话；编号进附录 |
| Modify: 锁旧文案的既有测试（见各 Task） | 断言改到新标签，物理数字不改 |
| Docs: `Plans/Delivery/status.md`、`decisions.md` ADR-017 | 账本 |

---

### Task 1: 呈现层 `UserFacingCopy`

**Files:**
- Create: `Packages/SimuKit/Sources/SimuCore/UserFacingCopy.swift`
- Create: `Packages/SimuKit/Tests/SimuCoreTests/UserFacingCopyTests.swift`

**Interfaces:**
- Consumes: `WallFace`、`OpeningKind`、`ParameterSource`、`RunState`、`QualityState`、`ResultFreshness`、`Opening`、`Seat`、`RoomGeometry`
- Produces: 下列 API，后续任务只调用它们，禁止在 View 里手写 `L1` / `z0`

```swift
public enum UserFacingCopy: Sendable {
    public static let forbiddenDefaultTokens: [String]
    public static func fieldTitle(_ path: String) -> String
    public static func wallTitle(_ wall: WallFace) -> String
    public static func sourceTitle(_ source: ParameterSource) -> String
    public static func metricTitle(_ name: String) -> String
    public static func runStateTitle(_ state: RunState) -> String
    public static func qualityTitle(_ quality: QualityState) -> String
    public static func freshnessTitle(_ freshness: ResultFreshness?) -> String
    public static func openingTitle(kind: OpeningKind, wall: WallFace, indexOnWall: Int, countOnWall: Int) -> String
    public static func seatTitle(index: Int, near: SeatPlace) -> String
    public static func furnitureTitle(index: Int) -> String
    public static func terminalTitle(isSupply: Bool) -> String
    public static func comfortKeyTitle(_ key: String) -> String
    public static func omittedAssumptionTitle(_ note: String) -> String
    public static func containsForbiddenDefaultToken(_ text: String) -> Bool
}

public enum SeatPlace: Sendable {
    case nearWindow, nearDoor, other
}
```

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SimuCore

@Test func fieldTitlesNeverEchoRawPaths() {
    let samples = [
        "hvac.setpointC", "hvac.supply", "occupancy.occupantCount",
        "geometry.openings.W1.z0", "occupancy.comfort.mrtC", "occupancy.comfort.clo"
    ]
    for path in samples {
        let title = UserFacingCopy.fieldTitle(path)
        #expect(!title.contains("hvac."))
        #expect(!title.contains("z0"))
        #expect(!title.contains("mrtC"))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(title))
    }
    #expect(UserFacingCopy.fieldTitle("hvac.setpointC") == "空调设定温度")
    #expect(UserFacingCopy.fieldTitle("occupancy.comfort.mrtC") == "周围表面温度")
}

@Test func wallsAndOpeningsUseRoomLanguage() {
    #expect(UserFacingCopy.wallTitle(.xMin) == "左墙")
    #expect(UserFacingCopy.wallTitle(.xMax) == "右墙")
    #expect(UserFacingCopy.wallTitle(.yMin) == "近侧墙")
    #expect(UserFacingCopy.wallTitle(.yMax) == "远侧墙")
    #expect(UserFacingCopy.openingTitle(kind: .window, wall: .xMax, indexOnWall: 0, countOnWall: 1) == "右墙的窗")
    #expect(UserFacingCopy.openingTitle(kind: .door, wall: .yMin, indexOnWall: 1, countOnWall: 2) == "近侧墙的门 2")
    #expect(UserFacingCopy.seatTitle(index: 0, near: .nearWindow) == "靠窗座位 1")
    #expect(UserFacingCopy.terminalTitle(isSupply: true) == "出风口")
    #expect(UserFacingCopy.terminalTitle(isSupply: false) == "回风口")
}

@Test func metricAndStateTitlesHideSolverNames() {
    #expect(UserFacingCopy.metricTitle("q_cool_w") == "制冷需求")
    #expect(UserFacingCopy.metricTitle("p_elec_w") == "空调用电功率")
    #expect(UserFacingCopy.metricTitle("seat_t_c_min") == "座位最凉")
    #expect(UserFacingCopy.metricTitle("seat_t_c_max") == "座位最热")
    #expect(UserFacingCopy.metricTitle("seat_u_mag_max") == "座位最大风速")
    #expect(UserFacingCopy.metricTitle("seat_pmv_min") == "冷热是否合适（偏低）")
    #expect(UserFacingCopy.metricTitle("seat_ppd_max") == "可能觉得不舒服的比例")
    #expect(UserFacingCopy.runStateTitle(.solving) == "正在估算")
    #expect(UserFacingCopy.qualityTitle(.passed) == "已通过检查")
    #expect(UserFacingCopy.qualityTitle(.failed) == "未通过检查")
    #expect(UserFacingCopy.freshnessTitle(.stale) == "房间改过了，请重新估算")
    #expect(UserFacingCopy.omittedAssumptionTitle("omitted: envelope_u_value") == "墙的保温尚未填写，不会按 0 计算")
}

@Test func defaultCopyRejectsForbiddenTokens() {
    let titles = [
        UserFacingCopy.metricTitle("q_cool_w"),
        UserFacingCopy.fieldTitle("geometry.openings.W1.s0"),
        UserFacingCopy.freshnessTitle(.stale),
        UserFacingCopy.comfortKeyTitle("clo")
    ]
    for text in titles {
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(text))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/SimuKit --filter UserFacingCopyTests`

Expected: FAIL，`UserFacingCopy` 未定义。

- [ ] **Step 3: Write the mapping**

实现要点：

- `fieldTitle` 取路径最后一段再查表；`openings.*.z0` →「离地高度」，`s0` →「沿墙起点」，`s1` →「沿墙终点」，`z1` →「上沿高度」。
- `comfort` 上下文：`mrtC` →「周围表面温度」，`rhPct` →「湿度」，`clo` →「衣着」，`met` →「活动强度」。
- `omittedAssumptionTitle`：`envelope_u_value` → 墙保温；`weather_file` → 天气文件；`furniture_boxes` → 家具尚未细画。未知 omitted 记「有一项尚未填写，不会按 0 计算」。
- `forbiddenDefaultTokens` 精确匹配词，避免误伤「湿度」里的无关字母。用整词/符号列表：`L1`、`L2`、`z0`、`z1`、`s0`、`s1`、`q_cool_w`、`p_elec_w`、`inputHash`、`PMV`、`PPD`、`mrtC`、`JSONL`、`stale`、`EnergyPlus`、`OpenFOAM`、`xMin`。
- `containsForbiddenDefaultToken` 对用户句做包含检查（大小写敏感，与界面中文混排一致）。

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/SimuKit --filter UserFacingCopyTests`

Expected: PASS。

- [ ] **Step 5: Suggested commit**

```text
Add a user-facing copy map so views never print model paths.
```

---

### Task 2: 导航、空状态、按钮与任务句

**Files:**
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`（`WorkspaceDestination.title`、`engineStatus`、`runMessage`、`evidenceExportLabel`、`blockedExportStatus`、`evidenceOnlyNarratorStatus`）
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`（空状态、工具栏保持「打开 / 保存 / 模板」）
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/WorkspaceReportTests.swift`（导出按钮文案）
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/WorkspaceL1Tests.swift`（若断言旧 `engineStatus` 字面量）

**Interfaces:**
- Consumes: `UserFacingCopy`
- Produces: 用户可见导航与动作名如下，API 名 `submitL1()` / `canSubmitL1` **不改**

| 内部 | 用户看见 |
|---|---|
| `.workspace` | 布置房间 |
| `.runs` | 用电与舒适 |
| `.scenarios` | 方案对比 |
| `.reports` | 带走结论 |
| `submitL1` 按钮 | 估算这一天用电 |
| `submitL2` 按钮 | 查看座位冷热分布 |
| `pinCurrentAsCandidate` | 加入对比 |
| `evidenceExportLabel` | 导出对比说明 |
| 未配置引擎 | 还不能估算。请在「计算准备」里选择计算文件夹。 |
| L1 失败 | 这一天的用电还算不出来，不会用 0 代替。 |
| L2 失败 | 座位冷热还看不出来，不会写成 0 度。 |
| 正在求解 | 正在估算… |

- [ ] **Step 1: Write / update the failing assertions**

```swift
@Test func destinationTitlesAreUserGoals() {
    #expect(WorkspaceDestination.workspace.title == "布置房间")
    #expect(WorkspaceDestination.runs.title == "用电与舒适")
    #expect(WorkspaceDestination.scenarios.title == "方案对比")
    #expect(WorkspaceDestination.reports.title == "带走结论")
    for destination in WorkspaceDestination.allCases {
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(destination.title))
    }
}

// 改 WorkspaceReportTests：
#expect(WorkspaceStore.evidenceExportLabel == "导出对比说明")
#expect(WorkspaceStore.evidenceExportLabel != "生成报告")
#expect(WorkspaceStore.evidenceExportLabel != "导出证据 PDF")
```

- [ ] **Step 2: Run to verify fail**

Run: `swift test --package-path Packages/SimuKit --filter destinationTitlesAreUserGoals`

Expected: FAIL，标题仍是「房间工作区」等。

- [ ] **Step 3: Replace user-visible strings**

`WorkspaceDestination.title`：

```swift
case .workspace: "布置房间"
case .scenarios: "方案对比"
case .runs: "用电与舒适"
case .reports: "带走结论"
```

空状态（`WorkspaceView`）：

- 无项目：「从一个办公室或教室模板开始，或打开已有房间。」不要写 L1 / 引擎尚未接入。
- 无计算：「布置好房间后，在这里估算这一天用电，并查看座位冷热。」
- 无对比：「先完成估算，再把结果加入对比。」
- 无报告：「加入通过检查的方案后，这里给出结论。没有方案时不能导出。」

`engineStatus` / `runMessage` 全部走用户句。内部日志、JSONL `monitor` 仍可含求解器名，但只进 Task 4 的折叠「计算过程」。

- [ ] **Step 4: Run targeted tests + compile**

Run:

```bash
swift test --package-path Packages/SimuKit --filter UserFacingCopyTests
swift test --package-path Packages/SimuKit --filter WorkspaceReportTests
swift test --package-path Packages/SimuKit --filter WorkspaceL1Tests
```

Expected: PASS。`engineStatus` 仍不得含 `/Users/`。

- [ ] **Step 5: Suggested commit**

```text
Rename navigation and actions to user goals instead of pipeline names.
```

---

### Task 3: 检查器总表加折叠

**Files:**
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/RoomEditorForm.swift`
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/UserFacingCopyTests.swift`（开口/座位标题）

**Interfaces:**
- Consumes: `UserFacingCopy.fieldTitle` / `wallTitle` / `openingTitle` / `seatTitle` / `sourceTitle`
- Produces: 检查器默认三块；提交按钮从本文件删除（改由 Task 4 的「用电与舒适」页触发同一 `store.submitL1()` / `submitL2()`）

默认展开（不要 `DisclosureGroup`，或 `isExpanded: true` 且标题就是块名）：

1. **房间** — 尺寸（长/宽/高，米）、朝向（「哪面墙朝北」，单位度）、门窗、家具
2. **使用** — 人数、上班时段、座位（「检查点，用来看坐在这里舒不舒服，不是多一个发热的人」）
3. **空调** — 设定温度、出风温度、出风口/回风口位置、风速、风量、室外新风

默认折叠：

- **电价** — 单价、币种、出处；脚注「只算选定的一天，不是全年，改造待报价」
- **查看假设** — `lockedAssumptions` 与 `listedAssumptions` 经 `omittedAssumptionTitle` / `fieldTitle` 翻译
- **计算准备** — 引擎目录选择、当前是否可以估算（人话）。**无提交按钮**
- iOS 同样分组；「编辑房间参数」入口文案可改为「编辑房间」

坐标字段标签：

| 内部 | 标签 |
|---|---|
| s0 | 沿墙起点 |
| s1 | 沿墙终点 |
| z0 | 离地高度 |
| z1 | 上沿高度 |
| 原点 x/y/z | 左右 / 前后 / 离地（米） |
| 座位 x/y/z | 左右 / 前后 / 坐姿高度（米） |
| 墙面 rawValue | `UserFacingCopy.wallTitle` |

开口标题用 `openingTitle`，不要「窗 W1」。座位用 `seatTitle`：按与最近窗/门的距离分类（窗优先，阈值用房间短边的 1/3，实现放在 `UserFacingCopy` 旁的小函数 `SeatPlace.classify(seat:geometry:)`，本 Task 写入 `UserFacingCopy.swift`）。家具「家具 1」「家具 2」。

朝向说明改为：「0° 表示近侧墙的对面是北。改朝向不会自动转动已经放好的门窗。」禁止 `+Y`、`s0/s1`。

「可覆盖项」并入「查看假设」或删掉独立段，路径必须翻译。

保留「应用…」按钮，本轮不改成即时绑定。

- [ ] **Step 1: Add classification tests**

```swift
@Test func officeTemplateSeatNearWindowIsNamedForTheUser() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let geometry = try #require(draft.geometry)
    let seats = try #require(draft.occupancy?.seats)
    let places = seats.map { SeatPlace.classify(seat: $0, geometry: geometry) }
    #expect(places.contains(.nearWindow))
    let titles = seats.enumerated().map { UserFacingCopy.seatTitle(index: $0, near: $1) }
    for title in titles {
        #expect(!title.hasPrefix("S"))
        #expect(!UserFacingCopy.containsForbiddenDefaultToken(title))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Expected: `SeatPlace.classify` 未定义。

- [ ] **Step 3: Implement classify + regroup the form**

`SeatPlace.classify`：对每个座位算到每扇窗/门墙面补丁中心的水平距离；最近且小于 `0.35 * min(sizeX, sizeY)` 则归窗或门，否则 `.other` →「座位 1」。

`WallPicker`：`Text(UserFacingCopy.wallTitle(face))`，不要 `face.rawValue`。

从 `RoomEditorForm` 删除「提交代表日 L1 / 提交代表工况 L2 / 取消任务」。取消仍可留在「用电与舒适」。

- [ ] **Step 4: Compile both apps**

Run: `Scripts/check.sh test` 中与 Workspace / UserFacing 相关的 Swift 测试，再 `Scripts/check.sh mac`（若本机 Xcode 可用）。

Expected: 编译过；检查器源码中默认展开段的 `Text(` / `NumericField(` / `Button(` 字面量不含禁止词。可用：

```bash
rg -n "L1|L2|z0|s0|q_cool_w|EnergyPlus|OpenFOAM|PMV|inputHash|JSONL" \
  Packages/SimuKit/Sources/SimuWorkspace/RoomEditorForm.swift
```

允许留下的：函数参数名 `s0:`、内部 `applyOpening(..., s0:)`。不允许留下的：`NumericField("s0"`、`Text("s0"`、按钮「提交代表日 L1」。

- [ ] **Step 5: Suggested commit**

```text
Fold the inspector into room, use, and cooling sections with plain labels.
```

---

### Task 4: 「用电与舒适」页 — 决策层 + 折叠

**Files:**
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`（`runsDetail`）
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`（`metricText` 显示走 `metricTitle`；值的单位保留）

**Interfaces:**
- Consumes: `store.metricText`、`dayEnergyText`、`dayCostText`、`UserFacingCopy`
- Produces: 未折叠区域只有决策数字；求解细节进两个 `DisclosureGroup`

默认看见：

1. 一句状态：`freshnessTitle` + `qualityTitle`（「已通过检查」/「还没有结果」）
2. 这一天预计用电（kWh）、费用（货币）
3. 座位最凉–最热（有 L2 且质量通过时；否则「还没有座位温度」）
4. 合适的座位（`SeatFeasibility.coverageText` 的新文案，见 Task 5）
5. 按钮：估算这一天用电、查看座位冷热分布、加入对比、取消

折叠「查看依据与限制」：

- 制冷需求与空调用电功率必须分列
- 费用 = 电功率 ÷ 1000 × 占用小时 × 电价，不是全年
- 改造待报价，不出回收期
- 座位是检查点不是热源
- 这是稳态，不是开机降温时间
- 达标不是问卷满意率

折叠「计算过程」：

- 进度事件用人话：`accepted` →「已接受」，`solving` →「正在估算」，`completed` →「完成」。`payload.monitor` 若含求解器名，显示「气流场求解」/「能耗计算」，不要把 `buoyantBoussinesqSimpleFoam` 写进默认或第一层折叠标题
- 切片高度、有效格点
- 出风温度 vs 设定温度、新风 vs 循环风（数字保留，标签人话）

删除默认区的：全年电量行（或移进依据并保持「未知」）、`L1 新鲜度`、`L2 边界（未跑 OpenFOAM）`、原始 `event.eventType.rawValue` 列表。

`metricText` 的标签由调用方用 `metricTitle`；值仍是 `"1033.112 W"`。stale 后缀用 `freshnessTitle(.stale)`，不要「非当前草稿」。

- [ ] **Step 1: Grep guard after edit**

默认 `runsDetail` 闭包（折叠外）不得出现禁止词。折叠内允许「制冷需求」等，仍禁止 `L1` `OpenFOAM` `JSONL`。

- [ ] **Step 2: Wire the four buttons**

同一 `Task { await store.submitL1() }` 等，只换标签与 `.disabled`。

- [ ] **Step 3: Run existing store tests**

Run: `swift test --package-path Packages/SimuKit --filter WorkspaceL1Tests`

Expected: PASS（提交 API 未改）。

- [ ] **Step 4: Suggested commit**

```text
Show day energy and seat comfort first; hide solver events behind disclosure.
```

---

### Task 5: 对比卡五要素 + 建议人话

**Files:**
- Modify: `Packages/SimuKit/Sources/SimuCore/SeatFeasibility.swift`（仅 display 字符串）
- Modify: `Packages/SimuKit/Sources/SimuCore/Recommendation.swift`（title/detail 字面量）
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`（`candidateCard`、`scenariosDetail`）
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/SeatFeasibilityTests.swift`
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/RecommendationTests.swift`（若断言旧 title）

**Interfaces:**
- Consumes: 现有 `CandidateRun` 字段
- Produces: 未折叠对比卡只含五要素；建议卡默认一句人话 +「查看依据与限制」

**对比卡默认：**

1. 方案名（已有 `record.name`，可后续加 TextField；本轮至少不要印 UUID）
2. 共用色标视口（已有）
3. 座位最凉–最热
4. 合适的座位
5. 这一天预计用电、费用

**对比卡折叠「查看依据与限制」：**

- 人数、时段、设定温度、出风温度是否相同（已有 `basisMismatchText`，改成「人数或使用时间不同，不能直接比」）
- 电功率、风速、冷热指数、最不合适的座位
- 计算编号（run 短号）——第二层或同一折叠底部，标签「计算编号」，不要 `inputHash`

**覆盖文案：**

```swift
public static let coverageLabel = "合适的座位"
public static let worstSeatLabel = "最不合适的座位"

// coverageText 有值时：
// "4 个中 3 个合适"   // 不要先写 75%
// 省略时仍是「不可评价」，不是 0%
```

`SeatFeasibilityTests.comparisonLabelsAreModelCoverageNotSatisfactionRate` 改为断言新标签，并继续禁止「满意率」。`coverageText == "100%（4/4）"` 改为 `"4 个中 4 个合适"`。全失败 `"0%（0/3）"` 改为 `"3 个中 0 个合适"`。

存储的 `worst_seat_reason` 仍可含「温度门」（证据稳定性）；**界面**用映射：

| 存储 | 显示 |
|---|---|
| 温度门 | 偏热或偏冷 |
| 风速门 | 风偏大 |
| PMV门 | 冷热不合适 |

该映射放 `UserFacingCopy.gateTitle(_:)`。`comparisonRows` 的 worst 值走映射后的句子：「靠窗座位 4：偏热或偏冷」。座位显示名若卡片没有 geometry 上下文，可先写「座位 4」，不要只丢 `S4`。

**建议卡：**

| 现 title | 新 title | 默认摘要 |
|---|---|---|
| 无质量通过场 | 还不能比较 | 这些方案还没有通过检查的气流结果。 |
| 已评座位均未通过模型门 | 这些座位目前都不合适 | 先看温度和吹风，再谈哪个方案更好。 |
| 口径不同 | 使用条件不同 | 人数、时间或设定温度不一样，不能直接比。 |
| 约束：部分座位未过模型门 | 有的座位还不合适 | 先看不合适的座位，再比较舒适和电费。 |
| 舒适：送风高度 | 出风口高度不同 | 同样使用条件下，出风口高低改变了座位冷热。 |
| 运行：代表日电费 | 哪天更省电 | 「方案甲」这一天预计费用较低。无差额则写「费用相同」。 |
| 改造：设备与安装 | 若要换设备 | 更换设备需要报价，现在是待报价。 |

`detail` 可保留数字依据，但放进 `DisclosureGroup("查看依据与限制")`。默认只显示 title + 一句摘要（可把现 `detail` 拆成 `summary` 本地变量，或截第一句）。引用按钮显示方案名，不要 `uuidString`；点击仍 `focusCitedRun`。

- [ ] **Step 1: Update SeatFeasibility tests first**

改标签断言 → 跑红 → 改 `coverageLabel` / `coverageText` → 跑绿。

- [ ] **Step 2: Update recommendation titles**

`RecommendationTests` 继续锁 kind、cited IDs、「推荐方案」「满意率」「全局最优」。不要把新 title 写成含 `L2` / `PMV`。

- [ ] **Step 3: Restyle `candidateCard`**

删未折叠的 `run … · 输入哈希`。`HStack` 状态用 `qualityTitle` / `freshnessTitle`。

`comparisonSavingsText`：「这一天电费相差 0.000 HKD」→「这一天预计费用相差 %.3f %@（按两次估算的用电功率相减，不是系数）」。不要 `L1`。

- [ ] **Step 4: Run**

```bash
swift test --package-path Packages/SimuKit --filter SeatFeasibilityTests
swift test --package-path Packages/SimuKit --filter RecommendationTests
swift test --package-path Packages/SimuKit --filter WorkspaceComparisonTests
```

Expected: PASS。

- [ ] **Step 5: Suggested commit**

```text
Show five decision facts on comparison cards and fold the audit fields.
```

---

### Task 6: 报告页与 PDF 正文

**Files:**
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`（`reportCard`）
- Modify: `Packages/SimuKit/Sources/SimuReporting/EvidencePDFAssembler.swift`
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/ReportEvidenceTests.swift`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`（`blockedExportStatus` 等）

**Interfaces:**
- Consumes: `ReportEvidence`、`UserFacingCopy`
- Produces: 页内与 PDF **正文**无人话以外的字段名；哈希与 UUID 只出现在 PDF「详细编号」附录

页面：

- 卡片：`kind.label` 改为 说明 / 用电 / 座位舒适 / 改造（改 `RecommendationKind.label`）
- 引用：方案名按钮，不是 UUID
- 假设：`comfortKeyTitle` + 数值 + 出处
- 导出：「导出对比说明」；iOS：「对比说明在 Mac 上导出。」
- `blockedExportStatus`：「有方案未通过检查、座位都不可评价，或使用条件不同，不能导出有效结论。」

PDF `render` 结构：

```
对比说明
电价说明：…
座位合适范围：23–26 °C（计算用的温度带，不是问卷）

方案
<name>    合适的座位    这一天用电    这一天费用    出风口离地

查看依据与限制
（现有 detail / assumptions）

详细编号
方案名    计算编号    输入指纹    检查结果
```

`ReportEvidenceTests` 里「必须含 inputHash」改为：附录含 hash，正文标题是「对比说明」且含方案名；正文前半（到「详细编号」之前）不含 `inputHash` 字样。数字（10.33112、12.397、座位带）仍必须出现。

舒适假设行：`周围表面温度 25 °C …`，不要 `mrtC`。

- [ ] **Step 1: Update PDF tests to the new outline**
- [ ] **Step 2: Implement `render`**
- [ ] **Step 3: Run `ReportEvidenceTests` `WorkspaceReportTests` `NarratorGuardTests`**

Expected: PASS。叙述守卫仍按证据数字集合过滤，与标题无关。

- [ ] **Step 4: Suggested commit**

```text
Write the report and PDF in room language and move hashes to an appendix.
```

---

### Task 7: 视口读得懂（非 3D）

**Files:**
- Modify: `Packages/SimuKit/Sources/SimuVisualization/SlicePalette.swift`
- Modify: `Packages/SimuKit/Sources/SimuVisualization/SimulationViewport.swift`
- Modify: `Packages/SimuKit/Sources/SimuVisualization/RoomScene.swift`
- Modify: `Packages/SimuKit/Sources/SimuVisualization/RoomWireframeView.swift`
- Modify: `Packages/SimuKit/Tests/SimuVisualizationTests/SlicePaletteTests.swift`
- Modify: `Packages/SimuKit/Tests/SimuVisualizationTests/RoomSceneTests.swift`

**Interfaces:**
- Consumes: `UserFacingCopy`（`SimuVisualization` 已依赖 `SimuCore`）
- Produces: 图例与空状态人话；座位 VoiceOver 用显示名。**不画门、不画家具、不加 RealityKit**

```swift
// SlicePalette.legendText
String(format: "坐姿高度 %.1f – %.1f °C · 蓝凉红热", minC, maxC)

// SimulationViewport 无几何
EmptyStateView("布置房间", symbol: "cube.transparent",
    message: "先填写房间的长宽高。没有完整房间时不会画示意图。")
```

`RoomScene` 增加 `seatDisplayNames: [String]`（与 `seats` 对齐），用 Task 3 的 `SeatPlace.classify`。`accessibilitySummary` 读这些名字，不读 `S1`。

`RoomWireframeView` 可在座位点旁画 `seatDisplayNames` 短标签（Canvas `context.draw(Text(...))`）。这不是 3D，也不是补家具。

- [ ] **Step 1: Extend legend test**

```swift
@Test func slicePaletteLegendStatesSeatHeightAndColdWarm() {
    let palette = SlicePalette(minC: 23.9, maxC: 25.9)
    #expect(palette.legendText.contains("23.9"))
    #expect(palette.legendText.contains("坐姿高度"))
    #expect(palette.legendText.contains("蓝凉红热"))
    #expect(!palette.legendText.contains("L2"))
}
```

- [ ] **Step 2: Run fail, then implement**
- [ ] **Step 3: RoomScene test that office seats include 靠窗 and never equal raw id in displayNames**
- [ ] **Step 4: `Scripts/check.sh test` 中 Visualization 10+ 项仍绿**
- [ ] **Step 5: Suggested commit**

```text
Explain the temperature legend and name seats in room language.
```

---

### Task 8: 整支验证与账本

**Files:**
- Modify: `Plans/Delivery/status.md`
- Modify: `Plans/Delivery/decisions.md`（ADR-017，本计划落地后填验证）
- Modify: `Plans/Phases/UX-user-facing-ui/UX-checklist.md`

- [ ] **Step 1: Run the full Swift suite**

```bash
Scripts/check.sh test
```

Expected: 既有物理/契约测试全绿。允许因文案更新而改断言，不允许改钉版瓦数、座位温度、10.33112 kWh / 12.397 HKD。

- [ ] **Step 2: Compile both apps if Xcode 可用**

```bash
Scripts/check.sh mac
Scripts/check.sh ios
```

- [ ] **Step 3: Hand-check list（Debug，沿用现有办公室模板）**

1. 左侧是「布置房间 / 用电与舒适 / 方案对比 / 带走结论」
2. 检查器打开先看到房间、使用、空调；要滚才看到电价/假设/计算准备
3. 门窗标签是「右墙的窗」，墙面是「左墙」不是 `xMin`
4. 「用电与舒适」能估用电、看座位冷热、加入对比
5. 对比卡未展开看不见哈希、PMV、UUID
6. 色标含「坐姿高度」「蓝凉红热」
7. 导出 PDF 首页是「对比说明」，哈希在「详细编号」
8. 改人数后费用旁出现「房间改过了，请重新估算」，数字不是 0

- [ ] **Step 4: 更新 `status.md` 下一步与证据行；ADR-017 写验证命令**
- [ ] **Step 5: Suggested commit**

```text
Record the user-facing UI pass and keep 3D on the later ADR-016 track.
```

---

## 本轮明确不做

- RealityKit / `RealityView` / 实体房间（ADR-016，第一轮完成后再开）
- 视口补画门、家具
- 点谁改谁、拖拽
- 检查器即时绑定（去掉「应用」）
- 方案复制向导、「调高 1°C」自动候选
- 改 Python worker、schema、input hash、质量门、ISO 公式

---

## 第一轮完成后的 3D（不在本计划实施）

沿用 ADR-016：Canvas 线框保留为降级；RealityKit 另开工作包。那时才做实体感、轨道相机、门和家具网格。用户向文案层必须已经存在，3D 只换渲染器，不把 `z0` 画回界面。
