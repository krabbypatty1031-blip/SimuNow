# 跨端与 worker 协议

当前 `Schemas` 约束 ProjectDraft、SimulationRequest、RunReceipt。
`schemaVersion` 1 只有项目身份和坐标元数据，不是完整可求解模型。
`schemaVersion` 2 增加 `geometry` / `occupancy` / `hvac` 三分区；开口与风口用墙面局部坐标 `s0`/`s1` 加 `z0`/`z1`；送风同时给速度与体积流量。
不确定量可带可选 `reference` 与 `uncertainty`，空字符串不当作出处。
三分区齐全时 `hasCompletePhysicalModel` 为真，仍不表示引擎已接入。
JSON 使用 Swift Codable 默认 camelCase；worker `doctor` 是独立的能力探测消息，使用 snake_case，尚无实际任务消息。P3 冻结任务事件格式时明确 Codable CodingKeys，不隐式混用命名。

## 文件

- `Schemas/project-draft.schema.json`：Core.ProjectDraft（v1 身份，v2 完整物理分区）。
- `Schemas/simulation-request.schema.json`：Simulation.SimulationRequest。
- `Schemas/run-receipt.schema.json`：Core.RunReceipt。

夹具：`Fixtures/project-draft-v1.json`、`Fixtures/project-v2-office.json`、`Fixtures/templates/office.json`、`Fixtures/templates/classroom.json`。
使用 JSON Schema 2020-12。未来 numerical results、field header、events 在 P3/P4 实现时新增并验证，不用 receipt 代替完整结果。
完整目标格式、单位、哈希、版本、二进制轴序见 [数据契约计划](../Plans/04-data-contracts.md)。

修改接口需同步 Swift、Python、schema 与 fixture；破坏兼容改版本并提供迁移。包测试验证 draft round-trip、v1 不可求解、v2 设定温度与送风温度分字段、旧结果新鲜度和未配置引擎不可产生成功计算。
Python：`PYTHONPATH=Backend/src python3 -m unittest Backend.tests.test_project_model`。
