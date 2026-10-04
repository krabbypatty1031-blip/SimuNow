# 开发计划总入口

本计划将产品目标逐层落到设计、架构、数据、计算、阶段工作和验证。日期：2026-10-04。团队：3–4 人；比赛：48–72 小时。
**当前交付：P5 阶段门已关闭**（房间编辑、L1、L2、对比、守卫 PDF）。P6 / P7 未做。状态以 [Delivery/status.md](Delivery/status.md) 为准，不要把本目录里未改的旧阶段标题当成「引擎尚未接入」。

## 阅读地图

| 顺序 | 文档 | 要解决的问题 |
|---|---|---|
| 1 | [产品与范围](01-product-scope.md) | 为谁解决什么、比赛做到哪里 |
| 2 | [系统架构](02-architecture.md) | 模块如何协作、Mac / iOS 怎样复用 |
| 3 | [交互与视觉设计](03-experience-design.md) | 页面、状态、图层与对比流程 |
| 4 | [数据与文件契约](04-data-contracts.md) | 各模块交换什么数据 |
| 5 | [物理计算与决策](05-computation-and-decision.md) | 气流、能耗、舒适、成本如何求 |
| 6 | [排期与任务索引](06-roadmap-and-backlog.md) | 关键路径、时间、责任和依赖 |
| 7 | [阶段工作包](Phases/) | 每阶段可执行任务、技术、验收与降级。P5 之后：[用户向界面](Phases/UX-user-facing-ui/UX-user-facing-ui.md) → [3D 视口方案 A](Phases/3D-realitykit-viewport/3D-realitykit-viewport.md) |
| 8 | [验证计划](Delivery/validation.md) | 工程和物理可信度如何证明 |
| 9 | [平台与交付](Delivery/platform-and-release.md) | 两端兼容、运行时、打包与发布 |
| 10 | [风险](Delivery/risks.md)、[决策](Delivery/decisions.md) | 不确定性与取舍 |
| 11 | [当前状态](Delivery/status.md)、[验证记录](Delivery/verification.md) | 计划和已实现的区别 |

## 阶段依赖

```text
P0 工程骨架
  ├── P1 物理技术验证 ──────────────┐
  └── P2 房间模型与编辑 ───────────┤
                                  P3 任务与能耗
                                      ↓
                                  P4 CFD 与结果
                                      ↓
                                  P5 决策与报告 → 比赛交付门槛（已关闭）
                                      ↓
                                  UX 用户向界面（呈现，不改物理）
                                      ↓
                                  3D 视口方案 A（ADR-016，只读 RealityKit）
                                      ↓
                                  P6 iOS 采集与现场校准（未做）
                                      ↓
                                  P7 优化、批量与产品加固（未做）
```

P0–P5 与后续 UX / 3D 呈现已落地到 Mac Debug。P1 / P2 的研发当时可以并行；现在集成路径是：统一草稿 → L1 EnergyPlus → 当前 L1 边界写入 L2 → 质量门 → 对比 / PDF。
阶段编号表示依赖逻辑。P0 工程建立不代表物理已验证——那一步已经由 P1–P5 的证据完成；不要把「P0 骨架」当成当前仓库状态。

## 计划维护

- 状态唯一入口是 `Delivery/status.md`；工作项用固定 ID（如 P4-03）。
- 优先级：Must=比赛链路必需；Should=有时间增加；Later=产品阶段。
- 阶段验收附命令、运行 ID、截图或测量证据。
- 外部框架、标准与性能查官方现行资料；计划中的耗时和误差目标在实测后调整。
