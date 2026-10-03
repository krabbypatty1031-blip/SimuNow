# P5-01 可改项、舒适默认与筛选

**Files:**

- Modify: `Packages/SimuKit/Sources/SimuCore/ProjectModels.swift`（`OccupancyModel.comfort`）
- Modify: `Packages/SimuKit/Sources/SimuCore/BundledTemplateJSON.swift`
- Modify: `Fixtures/templates/office.json`、`classroom.json`、`Fixtures/project-v2-office.json`
- Modify: `Protocols/Schemas/project-draft.schema.json`
- Modify: `Backend/src/simunow_worker/l2_runner.py`（草稿 → `comfortInputs`）
- Modify: `Backend/src/simunow_worker/models/l2_accounting.py`（已接 `comfortInputs`，runner 必须真传）
- Create: `Packages/SimuKit/Sources/SimuCore/DecisionVariables.swift`
- Test: `Packages/SimuKit/Tests/SimuCoreTests/` 舒适默认与口径筛选
- Test: `Backend/tests/test_comfort.py` 或 `test_l2_runner.py`（草稿含 comfort 时 PMV 不再因缺键 omitted）
- Modify: `Plans/Delivery/status.md`（有测试证据后再写）

**Interfaces:**

- Consumes: P2 `ProjectDraft`、P4-06 `CandidateRun.ComparisonBasis`、ADR-010 / ADR-013
- Produces: `ComfortAssumptions`；`DecisionVariables`（几何可改 vs 口径字段）；`evaluate_l2` 收到草稿舒适四键
- 不产生：SciPy 枚举、L0 筛选、建议卡、PDF、电价

**约束：**

- 舒适四键：`clo=0.5`、`met=1.2`、`rhPct=50`、`mrtC=26`，source=`assumed`，各带 reference（见 ADR-013）
- MRT 不是 L2 气温，不是辐射场
- 缺任一键 → PMV omitted + reason，不填 0
- 教室模板同一组成人默认，另加假设「儿童人群未单独评价」
- 改人数/时段/设定/送风温度 = 换口径（已有 `basisMismatch`）；改送风口高度 = 同口径几何轴
- L0 未配置，禁止写 L0 筛选通过
- 本任务不自动跑 27 个候选

---

### P5-01a 草稿舒适假设

- [x] Swift `ComfortAssumptions`：`mrtC` / `rhPct` / `clo` / `met` 均为带 source/reference 的 `PhysicalQuantity`（或等价四字段）
- [x] 办公室/教室模板与 `BundledTemplateJSON` 写入 ADR-013 默认值
- [x] schema + Python 解析同步；v2 缺 `comfort` 仍可解码，不得填 0
- [x] 教室 `lockedAssumptions` 或 `geometry.assumptions` 含儿童披露

通过：office 模板四键齐全且 source=assumed。失败：教室默默当成人办公而不披露。

### P5-01b runner 传 comfortInputs

- [x] `l2_runner` 从 snapshot `occupancy.comfort` 组装四键；缺一则不传（或传残缺，会计侧 omitted）
- [x] 测试：完整四键 → 座位带 `pmv`/`ppd`（适用域内）；缺 clo → 三条舒适指标 omitted + reason 含 clo
- [x] 旧钉版 `Fixtures/task/result-l2.json` 无舒适输入时保持 omitted，另加带舒适的夹具，不覆盖旧数字口径

通过：有假设才有 PMV。失败：无假设填 PMV=0，或有假设仍 omitted。

### P5-01c 决策变量与筛选

- [x] `DecisionVariables`：列出几何轴（送风 z0/z1、墙面位置）与口径轴（人数、占用时段、设定、送风温度）
- [x] 筛选只作用于已 pin 的 `CandidateRun`：口径不同的子集标「不是有效比较」，不删除
- [x] 不调用 L0；不声称搜过设计空间

通过：两个同口径候选留下，一个改设定的候选带口径警示。失败：把改设定的方案静默当成同口径更优。
