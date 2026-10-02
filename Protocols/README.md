# 跨端与 worker 协议

P2-01 已实现项目输入 v2 与不可变场景输入快照，详见 [项目契约](project-model-v2.md)。输入模型与数值引擎分开；worker doctor 仍明确报告引擎未配置。

## 文件

- Schemas/project-document.schema.json：ProjectDocument v2。
- Schemas/scenario-input-snapshot.schema.json：ScenarioInputSnapshot v2，尚非运行请求。
- Schemas/project-draft.schema.json：保留 P0 ProjectDraft v1，通过显式迁移进入 v2。
- Schemas/simulation-request.schema.json、run-receipt.schema.json：保留 P0 任务边界，本轮未改变。

使用 JSON Schema 2020-12。项目与快照采用 camelCase；Swift 使用 ProjectCodec，Python 使用 models.ProjectCodec。Python 内部 snake_case 显式 alias 到相同 wire 名称。doctor 的 snake_case 消息是独立协议。

项目/schema 声明在 model spec、Python wire model 和类型注册处维护，通过生成器与 contracts 检查保持一致。新扩展类型新增 payload schema 与注册；破坏兼容的字段变化必须升级版本并迁移。已知非法 payload 不降级为未知，未知扩展保留并阻断计算。

完整目标文件包、未来事件、结果、单位和哈希见 [数据契约计划](../Plans/References/04-data-contracts.md)。结果/field header/events 在 P3/P4 扩展，receipt 不能代替数值结果。
