# P4-04 舒适适用性

**Files:** `Backend/src/simunow_worker/models/comfort.py`、`Backend/tests/test_comfort.py`、`Backend/src/simunow_worker/models/l2_accounting.py`（上下文键 `comfortInputs`）、`Protocols/Schemas/simulation-result.schema.json`（metrics `reason`、座位 `pmv`/`ppd`）、Swift `ResultMetric`/`SeatSample`、`Fixtures/task/result-l2.json`  
**依赖:** P4-03  
**不做:** 关掉方法输入限制装可评价；把达标座位比例叫实测满意率；儿童/睡眠默认套成人办公模型

**约束:** 缺 RH、MRT、clo、met 时 PMV omitted。超模型范围「不可评价」。

**实现口径（ADR-010）:** `pythermalcomfort` 未安装且不自动引入依赖，自逐行移植 ISO 7730 附录 D 规范性程序；锚点为附录 D 同算法的已发布输出（met 1.4 / clo 0.5 / RH 50：vr 0.22 → 0.17/5.6，vr 0.1 → 0.41/8.5）与标准 Table 2（PPD 5/10/26%）。var 取座位实测风速，久坐不做 Vag 附加。

### P4-04a 可评

- [x] 输入齐全时写 PMV/PPD，带方法名（`iso7730_pmv`，座位行 `pmv`/`ppd` + 聚合指标）

### P4-04b 不可评

- [x] 缺湿或超范围 → value null、omitted、原因字段（`reason` 列出缺失项或排除口径；部分超域聚合只覆盖可评座位并披露）
- [x] 不得填 PMV=0（`NotEvaluable` 守卫：ta/tr/v/clo/met/rh/pa/PMV 八项适用域，超域拒绝不猜值）
