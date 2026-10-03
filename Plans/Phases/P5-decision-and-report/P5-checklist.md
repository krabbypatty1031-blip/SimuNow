# P5 可验收清单

> 给执行者：按 `P5-01` → `P5-05` 顺序。勾选后把命令与证据写入 `Plans/Delivery/status.md`。

**Goal:** Mac 上对已固定的基准+候选给出达标比例、代表日演示电费、三类建议和可追溯 PDF。模型 API 只写叙述。失败场与缺数据不编造。

**已有、不得再当 P5 完成证据：** P4 并排对比、L1 瓦数、L2 座位温/切片、空的报告页。

**锁定（P5 全程沿用）：**

- ADR-013 成人办公舒适默认；缺键 omitted，不填 PMV=0
- ADR-014 演示电价 1.2 HKD/kWh；L1 无年指标；报告层全年电费见 ADR-020
- ADR-015 证据包出数字；ADR-019 DeepSeek 写正文；ADR-020 四节真实陈述；无 API 不能导出 PDF
- 达标比例是模型覆盖率，不是实测满意率
- 报告引用冻结 run，不读正在编辑的草稿
- 不宣称全局最优、不宣称合规检定
- 不把 Debug 关 sandbox 带进 Release
- 未配置引擎时不可点提交；未配置 DeepSeek 时不可导出对比说明
- 密钥不进仓库

## P5-01 可改项与舒适默认

- [x] P5-01a 模板写入 clo/met/RH/MRT 假设（ADR-013）；教室披露儿童未单独评价
- [x] P5-01b `run-l2` 传 `comfortInputs`；缺一键 omitted
- [x] P5-01c 决策变量区分几何轴与口径轴；不做 L0/SciPy 搜索

## P5-02 可行性

- [x] P5-02a 温度带 23–26 °C、风速 ≤0.25 m/s、有 PMV 则 |PMV|≤0.5
- [x] P5-02b 无场不写 0%；全失败有解释
- [x] P5-02c 文案不是满意率

## P5-03 费用

- [x] P5-03a 代表日 kWh 与 HKD；缺项 omitted
- [x] P5-03b `lastL1Result` / `lastL2Result` 分槽；pin 冻结费用

## P5-04 建议与 PDF

- [x] P5-04a 运行 / 舒适 / 改造三类卡，每卡有 run ID
- [x] P5-04b 证据 PDF（Core Graphics），数字=证据包；正文=DeepSeek
- [x] P5-04c 数字守卫：证据外数字拒用；无密钥不导出

## P5-05 演示

- [x] P5-05a 空/失败/无 API 路径诚实
- [x] P5-05b 办公室数字 + 证据 PDF（自动化已通；App Debug 2026-10-03 已点 L1→L2→固定→导出，见 `verification.md`）
