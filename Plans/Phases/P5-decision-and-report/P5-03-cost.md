# P5-03 演示电价与代表日费用

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/CostAssumptions.swift`
- Create: `Backend/src/simunow_worker/models/costing.py`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`（`lastL1Result` 与 `lastL2Result` 分槽）
- Modify: `Packages/SimuKit/Sources/SimuCore/CandidateRun.swift`（冻结 L1 电功率与代表日费用）
- Modify: `RoomEditorForm`：电价/币种可编辑，显示来源
- Test: `CostAccountingTests`；更新 `WorkspaceL2Tests`（提交 L2 后 L1 瓦数仍在）

**Interfaces:**

- Consumes: L1 `p_elec_w`、占用时段、ADR-014 电价
- Produces: `E_day_kWh`、`cost_day`（币种 HKD）、改造费 `omitted` +「待报价」
- 不产生：`annual_kwh` 有值、回收期、未跑 L1 的节电百分比

**约束：**

- 默认电价 1.2 HKD/kWh，source=`assumed`，reference=`比赛演示假设，非真实电价`
- `E_day_kWh = p_elec_w / 1000 × occupiedHours`；办公室 08:00–18:00 → 10 h
- 缺电价 / 缺 p_elec / 缺时段 → 费用 omitted，不填 0
- 改造费无报价来源 → 待报价，不出回收期
- 设定或风量变化后的「更省电」必须来自**另一次** L1 run 的 `p_elec_w` 之差，禁止乘经验系数
- 任务页分槽：`lastL1Result` 与 `lastL2Result` 互不覆盖（修 P4 单槽）

---

### P5-03a 会计

- [x] 测试：1033.112 W × 10 h → 10.33112 kWh → 12.397 HKD（1.2 HKD/kWh），币种 HKD
- [x] 测试：无电价 → cost_day omitted
- [x] 测试：无 p_elec_w → 电量与费用都 omitted
- [x] 测试：结果对象不含有值的 `annual_kwh` / `payback_years`

通过：日费有来源。失败：把一天乘 365 当全年。

### P5-03b 分槽与冻结

- [x] 提交 L2 后任务页仍显示上次同项目 L1 的冷量/电功率（哈希不同则标 stale，不把旧瓦数写成当前）
- [x] `pinCurrentAsCandidate` 把当时的 L1 费用快照进 `CandidateRun`；无 L1 则费用 omitted
- [x] 对比页并排代表日电费；口径不同不比节省额

通过：手测路径下先 L1 再 L2，费用还在。失败：交 L2 后电费变未知且报告缺运行费。
