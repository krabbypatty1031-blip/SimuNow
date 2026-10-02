# 跨端与 worker 协议

当前 `Schemas` 为 P0 Swift 类型的机器可读约束：ProjectDraft、SimulationRequest、RunReceipt。draft 只有项目身份和坐标元数据；不是完整可求解模型。
当前 JSON 使用 Swift Codable 默认 camelCase；worker `doctor` 是独立的能力探测消息，使用 snake_case，尚无实际任务消息。P3 冻结任务事件格式时明确 Codable CodingKeys，不隐式混用命名。

## 文件

- `Schemas/project-draft.schema.json`：Core.ProjectDraft。
- `Schemas/simulation-request.schema.json`：Simulation.SimulationRequest。
- `Schemas/run-receipt.schema.json`：Core.RunReceipt。

使用 JSON Schema 2020-12。未来 numerical results、field header、events 在 P3/P4 实现时新增并验证，不用 receipt 代替完整结果。
完整目标格式、单位、哈希、版本、二进制轴序见 [数据契约计划](../Plans/04-data-contracts.md)。

修改接口需同步 Swift、Python、schema 与 fixture；破坏兼容改版本并提供迁移。包测试当前验证 draft round-trip、旧结果新鲜度和未配置引擎不可产生成功计算。
