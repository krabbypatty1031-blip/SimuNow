# 跨端与 worker 协议

当前 `Schemas` 约束 ProjectDraft、SimulationRequest、RunReceipt、SimulationEvent、SimulationResult。
`schemaVersion` 1 只有项目身份和坐标元数据，不是完整可求解模型。
`schemaVersion` 2 增加 `geometry` / `occupancy` / `hvac` 三分区；开口与风口用墙面局部坐标 `s0`/`s1` 加 `z0`/`z1`；送风同时给速度与体积流量。
`occupancy.comfort`（`mrtC` / `rhPct` / `clo` / `met`）可选；缺任一键则 L2 PMV omitted + reason，不填 0。教室模板另披露「儿童人群未单独评价」。
`costAssumptions`（`pricePerKWh` / `currency` / `source` / `reference`）可选。缺电价、缺 `p_elec_w` 或缺占用时段时代表日电费 omitted，不填 0。默认演示价 1.2 HKD/kWh，source=`assumed`。不含有值的 `annual_kwh` 或 `payback_years`。改造费为「待报价」。
不确定量可带可选 `reference` 与 `uncertainty`，空字符串不当作出处。
三分区齐全时 `hasCompletePhysicalModel` 为真，仍不表示引擎已接入。
JSON 使用 Swift Codable camelCase，任务消息的 CodingKeys 显式写出。worker `doctor` 仍是独立探测，snake_case。P3-01 事件流是 JSONL，乱序 sequence / 截断行 / 错 runID 必须拒绝。

## 文件

- `Schemas/project-draft.schema.json`：Core.ProjectDraft（v1 身份，v2 完整物理分区）。
- `Schemas/simulation-request.schema.json`：Simulation.SimulationRequest（含相对快照路径与哈希）。
- `Schemas/run-receipt.schema.json`：Core.RunReceipt。
- `Schemas/simulation-event.schema.json`：Core.SimulationEvent（JSONL 单行）。
- `Schemas/simulation-result.schema.json`：Core.SimulationResult（可选 period / weatherPath / weatherHash / 送风与设定温度 / L2 qualityDetail 与 seatSamples）。

夹具：`Fixtures/project-draft-v1.json`、`Fixtures/project-v2-office.json`、`Fixtures/templates/office.json`、`Fixtures/templates/classroom.json`、`Fixtures/task/`。
使用 JSON Schema 2020-12。receipt 仍不是完整结果；指标缺失用 omitted/null，不填 0。field header 仍待 P4。
完整目标格式、单位、哈希、版本、二进制轴序见 [数据契约计划](../Plans/04-data-contracts.md)。

修改接口需同步 Swift、Python、schema 与 fixture；破坏兼容改版本并提供迁移。包测试验证 draft round-trip、v1 不可求解、v2 设定温度与送风温度分字段、旧结果新鲜度和未配置引擎不可产生成功计算。
L2 结果的 `qualityDetail` 七个门禁字段全部可选（缺日志不等于过门禁）；`seatSamples` 仅质量通过时出现，失败场省略而不是填 0；低风速座位带 `lowSpeedAbsoluteError` 标记。
指标行可带 `reason`：omitted 时说明缺什么或超范围，部分聚合时说明排除口径；P4-04 起 `seat_pmv_min` / `seat_pmv_max` / `seat_ppd_max` 由 ISO 7730 附录 D 算法产生，舒适输入（MRT/RH/clo/met）缺一项即 omitted + `reason`，不填 PMV=0；座位行可带 `pmv` / `ppd`（仅输入齐全且在适用域内时出现）。P5-02 在同一 `metrics` 数组追加 `seat_pass_ratio` / `seat_pass_count` / `seat_eval_count`（数值）以及 `worst_seat_id` / `worst_seat_reason` / `infeasibleReason`（标识与门文案在 `reason`，因为指标值是数字）。无质量通过场时这些行 omitted，不填比例 0。比例是模型门覆盖，不是实测满意率。域外或 omitted 座位不进分母，并在 `reason` 披露。
P5 将增加 `Schemas/report-evidence.schema.json`：报告数字只来自冻结 run，叙述器不得改指标。未落地前不要把空报告页当成已导出 PDF。

Python：`PYTHONPATH=Backend/src python3 -m unittest Backend.tests.test_project_model`。
