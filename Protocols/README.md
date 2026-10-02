# 跨端与 worker 协议

P2-01 已实现项目输入 v2 与不可变场景输入快照，详见 [项目契约](project-model-v2.md)。P1-01 新增 [doctor 环境协议](doctor-v1.md) 和 runtime manifest，真实环境探测与 SimuNow 求解管线状态分开。P3 新增 [RunInput](run-input-v1.md) 与 [run 事件流/结果](run-events-v1.md)，L0 运行链路可用；L1/L2/L3 仍未配置。

## 文件

- Schemas/project-document.schema.json：ProjectDocument v2。
- Schemas/scenario-input-snapshot.schema.json：ScenarioInputSnapshot v2。
- Schemas/project-draft.schema.json：保留 P0 ProjectDraft v1，通过显式迁移进入 v2。
- Schemas/simulation-request.schema.json、run-receipt.schema.json：保留 P0 任务边界，本轮未改变。
- Schemas/runtime-manifest.schema.json、doctor-report.schema.json：CLI 目标环境与实际诊断，独立 snake_case 协议；P0 顶层字段兼容。
- [run-input-v1.md](run-input-v1.md) + Schemas/run-input.schema.json：把快照提升为带哈希身份的运行请求。
- [run-events-v1.md](run-events-v1.md) + Schemas/run-event.schema.json、run-result.schema.json：worker JSONL 事件流、拒绝规则与原子结果文件。

使用 JSON Schema 2020-12。项目与快照采用 camelCase；Swift 使用 ProjectCodec，Python 使用 models.ProjectCodec。Python 内部 snake_case 显式 alias 到相同 wire 名称。doctor 的 snake_case 消息是独立协议。

项目/schema 声明在 model spec、Python wire model 和类型注册处维护，通过生成器与 contracts 检查保持一致。新扩展类型新增 payload schema 与注册；破坏兼容的字段变化必须升级版本并迁移。已知非法 payload 不降级为未知，未知扩展保留并阻断计算。

完整目标文件包、场数据格式与哈希范围见 [数据契约计划](../Plans/References/04-data-contracts.md)。运行事件/结果 v1 已实现；field header 在 P4 扩展，receipt 不能代替数值结果。
