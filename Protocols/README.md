# 跨端与 worker 协议

P2-01 已实现项目输入 v2 与不可变场景输入快照，详见 [项目契约](project-model-v2.md)。P1-01 新增 [doctor 环境协议](doctor-v1.md) 和 runtime manifest，真实环境探测与 SimuNow 求解管线状态分开；四级管线仍未配置。
P2-04 新增 [本地项目包 v1](project-package-v1.md)，包元数据属于 App 文档层，不改变 worker 的物理输入协议。

N1 新增 [Swift 本地分析 v1](native-analysis-v1.md)：独立 request/event/result/configuration/manifest，不改变 P0 或项目 v2。开发检查使用 `Scripts/check_native_analysis_contracts.sh`；App 运行不调用 Python 验证器。

## 文件

- Schemas/local-analysis-request.schema.json、local-analysis-event.schema.json、local-analysis-result.schema.json：本地方法与 typed payload。
- Schemas/analysis-configuration.schema.json、analysis-artifact-manifest.schema.json：独立本地配置与不可变 run 文件索引。
- Schemas/cost-evaluation.schema.json、comparison-snapshot.schema.json：N4固定父run的独立费用评价与纯值比较，精确货币数值使用Decimal字符串。
- Schemas/project-document.schema.json：ProjectDocument v2。
- Schemas/scenario-input-snapshot.schema.json：ScenarioInputSnapshot v2，尚非运行请求。
- Schemas/project-package-metadata.schema.json：App 项目包 v1 的基准/模板信息。
- Schemas/project-draft.schema.json：保留 P0 ProjectDraft v1，通过显式迁移进入 v2。
- Schemas/simulation-request.schema.json、run-receipt.schema.json：保留 P0 任务边界，本轮未改变。
- Schemas/runtime-manifest.schema.json、doctor-report.schema.json：CLI 目标环境与实际诊断，独立 snake_case 协议；P0 顶层字段兼容。

使用 JSON Schema 2020-12。项目与快照采用 camelCase；Swift 使用 ProjectCodec，Python 使用 models.ProjectCodec。Python 内部 snake_case 显式 alias 到相同 wire 名称。doctor 的 snake_case 消息是独立协议。

项目/schema 声明在 model spec、Python wire model 和类型注册处维护，通过生成器与 contracts 检查保持一致。新扩展类型新增 payload schema 与注册；破坏兼容的字段变化必须升级版本并迁移。已知非法 payload 不降级为未知，未知扩展保留并阻断计算。

完整目标文件包、未来事件、结果、单位和哈希见 [数据契约计划](../Plans/References/04-data-contracts.md)。外部引擎结果/field header 后续独立扩展；本地事件/结果采用 native-analysis-v1，receipt 不能代替结果。
