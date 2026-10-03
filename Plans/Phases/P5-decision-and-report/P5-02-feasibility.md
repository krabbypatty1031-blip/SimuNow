# P5-02 L2 可行性、达标比例、最差座位

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/SeatFeasibility.swift`
- Create: `Backend/src/simunow_worker/models/feasibility.py`
- Modify: `Backend/src/simunow_worker/models/l2_accounting.py`（追加指标，不改质量门）
- Modify: `Protocols/Schemas/simulation-result.schema.json`
- Test: Swift `SeatFeasibilityTests`；Python `test_feasibility.py`
- Modify: 对比页显示达标比例与最差座位（质量失败无比例）

**Interfaces:**

- Consumes: 质量通过的 `seatSamples`（tC、uMag、可选 pmv/ppd）、ADR-013 舒适假设
- Produces: `seat_pass_ratio`（0–1）、`seat_pass_count`、`seat_eval_count`、`worst_seat_id`、`worst_seat_reason`
- 不产生：电价、建议排序、PDF、把比例叫满意率

**约束：**

- 只评价 quality passed 且未被 omitted 的座位
- 域外 / 超 ISO 适用域座位不进分母，reason 披露排除口径
- 无质量通过场 → 全部可行性指标 omitted，不填比例 0
- 文案必须是「模型判据覆盖率」，禁止「满意率」「实测达标」
- 无可行方案（eval_count>0 且 pass_count=0）→ 解释触犯了哪条门，不推荐

**座位门（本阶段锁定，演示用，不是标准检定）：**

| 门 | 通过 | 说明 |
|---|---|---|
| 空气温度 | 23.0 ≤ tC ≤ 26.0 | 相对区设定 26 °C 的坐姿气温带 |
| 风速 | uMag ≤ 0.25 m/s | 办公静坐量级；低速绝对误差座位仍用该门并标记 |
| PMV | 有 pmv 时 −0.5 ≤ pmv ≤ 0.5 | 无 pmv 则本门不评（不因此判失败） |

座位通过 = 温度门 ∧ 风速门 ∧（无 pmv 或 PMV 门）。比例 = pass_count / eval_count。
最差座位：在已评座位中取偏离温度带中心（24.5 °C）最大者；并列再看风速。

---

### P5-02a 逐座位核算

- [x] 测试：4 座全在带内、风速 <0.25、有 PMV → ratio=1，worst 仍指出偏离最大座
- [x] 测试：1 座 27 °C → 该座失败，ratio=0.75，worst 为该座，reason 含温度门
- [x] 测试：1 座域外 omitted → eval_count=3，不把 omitted 当失败

通过：分母不含 omitted。失败：4 座里 1 个域外却按 4 算。

### P5-02b 无场 / 无可行

- [x] 质量失败或无 seatSamples → 比例 omitted + reason，不是 0%
- [x] 已评座位全部失败 → ratio=0 且 `infeasibleReason` 列出门，不生成「推荐方案」

通过：失败场无 0% 伪装。失败：把质量失败写成 0% 达标。

### P5-02c 文案

- [x] UI/报告标签用「模型判据座位覆盖」或「达标座位比例（模型）」
- [x] 测试或快照断言不含「满意率」
