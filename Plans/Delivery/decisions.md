# 架构决策记录

## ADR-001：双原生 target + 本地共享包（已接受）

背景：Mac 主工作区，iOS 后续采集与浏览；平台能力不同。
选择：两个入口、一份 SimuKit，业务/契约共享，执行与采集适配。
影响：平台编译可独立验证，避免 Process 泄漏移动端；维护两个最小入口。

## ADR-002：macOS14 / iOS17 + Swift6（已接受）

选择：基础 SwiftUI 导航与 Observation 兼容上述系统，并发检查完整。
影响：RealityView 等调用在实现时 availability 或改 renderer；提高系统版本同步 xcconfig、Package 与计划。

## ADR-003：外部 worker 与文件协议（已接受）

选择：不可变 run、JSON/JSONL、二进制场、Python 引擎 adapter。
影响：可复算、可缓存、可远程扩展；Mac sandbox/运行时打包需 P3 实证。

## ADR-004：稳定工况多保真度（已接受）

选择：比赛先 L0/L1/L2；单向边界；代理/瞬态后续。
影响：用户收到代表日与稳态位置评价；年度/降温时间需要另建数据和模型。

## ADR-005：占位明确不可用（已接受）

选择：空工作区、UnconfiguredSimulationClient 抛错、worker doctor 返回 not_configured。
影响：架构可开发，任何显示收益都要真实计算依据；人工 fixture 仅用于接口测试。

## ADR-006：P2 编辑不提供撤销（已接受）

日期：2026-10-03。
背景：P2-03g 要求先决定撤销范围，未实现却显示撤销会违反「无空按钮」。
选择：本阶段只编辑内存模型，不提供撤销栈；关闭未保存即丢失。
影响：P2-04 保存后以文件为真相；若以后要撤销，另开 ADR。
验证：`RoomEditorForm` 无撤销按钮。

## ADR-007：项目包为目录而非 zip（已接受）

日期：2026-10-03。
背景：P2-04 要求锁定 `*.simunow` 目录包或 zip 等价物。
选择：目录包 `Name.simunow/project.json`。先写 `FileManager.temporaryDirectory` 再替换目标，失败时保留旧 JSON。
影响：Mac 用 NSSavePanel/NSOpenPanel；iOS 用 folder/json 文件选择器。包路径只留在内存，不写入 project.json。P3 再在包内加 runs 快照。
验证：`PackageTests` 关闭重开与失败替换；工作区「打开 / 保存」绑定 `ProjectPackage`。

## 待决定

- P1：OpenFOAM 分支/版本/求解器/网格与湍流，EnergyPlus 版本与设备模型。
- P3：Mac helper/companion 运行时和权限桥接，事件/重启策略。
- P4：renderer 及各平台预算、舒适档案与边界。
- P5：PDF 实现与成本数据；P7：代理/远程/发布渠道。

每条新增决策记录触发原因、备选、选择、影响、验证证据与日期。
