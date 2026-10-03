# P2-05 模板、基准快照、P1 字段映射

**Files:**

- Create: `Fixtures/templates/office.json`、`Fixtures/templates/classroom.json`
- Create: `Packages/SimuKit/Sources/SimuCore/ProjectTemplates.swift`
- Create: `Packages/SimuKit/Sources/SimuCore/P1RoomMapping.swift`
- Create: `Backend/src/simunow_worker/models/p1_mapping.py`（与 Swift 对照同一夹具）
- Test: 模板 source 非空；映射键齐全
- 依赖：P2-01；P2-04 若要「另存为模板」则先有保存，否则只读夹具也算过

**Interfaces:**

- Consumes: v2 `ProjectDraft`
- Produces: 模板实例（新 UUID）；`P1RoomFields` 只读 DTO，不是 solver case
- 不产生：OpenFOAM 运行、假节能、envelope 必填

---

### P2-05a 办公室模板

- [x] 从 `Fixtures/templates/office.json` 创建项目，所有物理量有 `source`
- [x] 尺寸、一扇窗、分体空调、座位与 `Fixtures/project-v2-office.json` 同口径或文档说明差异
- [x] assumed 项进入假设列表

通过：加载模板后 `hasCompletePhysicalModel == true`。失败：模板缺 HVAC。

### P2-05b 教室模板

- [x] 更高占用、座位网格更密；参数有 source
- [x] 与办公室共用模型类型，不另起 schema

通过：教室座位 ID 稳定且点数 ≥ 办公室。失败：只改名字仍是办公室几何。

### P2-05c 基准快照

- [x] `scenarioID` 或等价身份：基准方案与「当前编辑」分开
- [x] 编辑当前房间不覆盖已冻结基准 JSON
- [x] 未做计算时基准只是输入快照，不带结果指标

通过：改当前 sizeX 后基准 sizeX 不变。失败：只有一份可变 draft。

### P2-05d 可覆盖项

- [x] 文档化哪些字段用户应改（设定温度、风口位置、人数）哪些是模板假设（U 值未建模则写 omitted）
- [x] UI 或假设列表能看到可覆盖 vs 锁定假设

通过：列表存在且与模板 JSON 一致。失败：口头「都可以改」无清单。

### P2-05e 映射到 P1 字段

- [x] 纯函数：`ProjectDraft` → 含 P1 `room_p1.json` 所需键的字典或结构（size、supply、return、window、gains、seats、l1 可用 omitted）
- [x] 窗面积用 `(s1-s0)*(z1-z0)`，不用墙宽
- [x] 不调用 EnergyPlus / OpenFOAM；不写 `quality.pass`
- [x] Swift 与 Python 对同一办公室模板映射的关键标量一致（尺寸、送风 T、座位数）

通过：单测断言窗面积 = 1.5×1.3，不是 6×1.3。失败：把 App JSON 直接当 solver 输入而不转换坐标说明。

envelope / 天气哈希：映射里标 `omitted` 或跳过 L1 专用键，不得填 0 充 U 值。
