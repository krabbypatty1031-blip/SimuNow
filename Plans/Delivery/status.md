# 实施状态

日期：2026-10-03。当前状态：P0 骨架、P2 房间编辑全套、P3 任务链路与 L0 能耗已验收；P1-01 部分完成（引擎未安装）。本文件只记录已实现事实。

| 项目 | 状态 | 证据 |
|---|---|---|
| Mac / iOS target、shared schemes | 已创建 | SimuNow.xcodeproj |
| 六个共享模块、空工作区 | 已创建 | Packages/SimuKit |
| draft、run 状态/身份、任务与报告协议 | 已创建 | Core/Simulation/Reporting |
| worker doctor + L0 自检 | 已实现 | runtime/{doctor,probe,selfcheck}；doctor l0=verified_available |
| 计划与 Agent 指南 | 已创建 | Plans / AGENTS.md |
| GitHub 版本管理 | origin/main；开发在 development 分支（= paco-development + P2/P3 提交），提交身份 iampaco / HONG Shangjing | https://github.com/krabbypatty1031-blip/SimuNow |
| P2-01 完整输入模型与契约 | 已完成 | Core/Project、Backend/models、Protocols/project-model-v2.md；verification.md |
| P2-02…05 向导/编辑/保存/模板 | 已完成（代码 + 测试通过；App 手动演示未记录） | Workspace/Home/Wizard/Editing、Core ProjectPackage/Templates；verification.md P2/P3 节 |
| P3 任务链路（RunInput/事件/结果/取消/哈希/新鲜度） | 已完成（本机 CLI 与进程级验证；App 内运行未验证，sandbox 桥接待 P7） | jobs/、RunProtocols、LocalSimulationClient、RunStore；verification.md P2/P3 节 |
| L0 稳态代表日能耗 | 已完成（集总平均估算，非 CFD；计算接线验证，非物理标定） | adapters/l0/steady_state.py、test_l0.py、contract_run.py |
| P1-01 固定运行环境与能力检查 | 部分完成：manifest、doctor、行为测试已实现；本机（tanchai）无容器工具与 EnergyPlus，引擎安装未授权 | runtime/；verification.md |
| L1/L2/L3 引擎 | 待开发（阻塞：Colima VM + OpenFOAM 镜像 + EnergyPlus 安装授权） | P1/P3 遗留条件 |
| 场渲染/舒适/成本对比/报告 | 待开发 | P4/P5 |
| RoomPlan/实测/代理/批量 | 待开发 | P6/P7 |

## 下一步

P3 已完成。下一步按依赖顺序：P5（方案对比、建议卡、基础 PDF，不依赖外部引擎）；P1-01 收尾需要授权安装 Colima VM、固定 OpenFOAM 镜像与 EnergyPlus 26.1.0 后才可继续 P1-02…05 与 P4 真实 CFD。
不要开始用示意场制作定量推荐。任何阶段完成都要添加 run/命令/验证依据。

## P2 房间编辑套件完成记录（2026-10-03，development 分支，提交 2ad08b2）

- 实现：`.simunow` 项目包（原子写、分类错误、v1 显式迁移）、办公室/教室模板（带来源预设与显式未知）、五步建房向导、俯视图编辑（吸附 0.05 m、边界钳制、选择身份）、参数检查器（单位+来源+未知原因）、校验列表（双门定位）、首页与最近项目、会话层（dirty/重校验）。
- 验证：见 verification.md 2026-10-03 P2/P3 节（本轮补录；该提交当时未更新 status/verification）。
- 限制：无结构性撤销（文本走系统原生，删除有确认，ADR-013）；3D 手柄不在本阶段；App 手动演示路径（建模板→编辑→保存→重开）未在本机记录截图。

## P3 任务链路与 L0 完成记录（2026-10-03，development 分支）

- 协议：Protocols/run-input-v1.md、run-events-v1.md + Schemas/run-input/run-event/run-result.schema.json；输入哈希为快照规范文本 SHA-256，双端实现且契约交换验证一致。
- worker：`python -m simunow_worker run --input --run-dir [--cancel-file]`；协议/身份/哈希先验校验（无效退出 3 无事件），事件 JSONL（stdout + tee events.jsonl），result.json 原子写，取消标记轮询（开始前取消也得 cancelled），失败保留 stderr.log 证据。
- L0 适配器：30 分钟步长代表日稳态热平衡；能量平衡交叉检查；未知参数产生 missing+原因，不为 0；电耗为等效 COP 口径；容量不足时按 deficit/总导纳估算室温偏移并标注。
- Swift：`RunProtocols.swift`（事件流解析：错 run/乱序/缺口/未知类型拒绝；RunResult 解码）、`LocalSimulationClient.swift`（macOS posix_spawn SETSID 进程组、stderr 落 worker-stderr.log、取消协作+进程组升级）、`RunStore`/`RunsView`/`ResultPanel`（提交门控、进度、取消、磁盘恢复、改输入即 stale）。
- doctor：新增 L0 真实自检（ADR-015），engines.l0=verified_available，l1/l2/l3 仍 not_configured。
- 验证与端到端命令：见 verification.md 2026-10-03 P2/P3 节。
- 限制：App 内发起运行未在 sandbox 下验证（子进程继承 sandbox，读取仓库路径被拒属预期；打包桥接待 P7 ADR）；GUI 演示需用户在本机跑一次；run 目录当前在 Application Support（ADR-014）。

## P2-01 完成记录

2026-10-02，开发分支 paco-development：完整项目/场景输入、语义单位与来源、矩形/盒体/单类空调、可组合规则、类型注册、v1 迁移、未知扩展无损保留、不可变场景输入快照及 Workspace/坐标接口已实现。

- 契约：Swift/Python 从共享结构清单生成强类型声明；JSON Schema 2020-12 含分类 payload 约束；生成漂移检查与独立 schema 验证。
- OCP 证据：独立测试模块注册设备并完成项目/快照/规则流程；自定义几何 containment 查询生效，无需修改项目聚合或中央类型分派。
- 验证：`Scripts/check.sh all` 在锁定依赖的独立 Python 环境中通过；Python 14 项、Swift 16 项（含原有 3 项）；2 份人工项目与快照的真实双向交换、28 类错误/兼容性案例；Mac 和 generic iOS Simulator Debug 编译通过。
- 限制：本轮无 UI 编辑、磁盘保存、真实天气/设备数据验证、运行哈希、数值引擎或物理结果；doctor 四级引擎仍为 not_configured。App 本次启动/最低系统运行未验证。
- 日志保存在忽略的 `Artifacts/P2-01/`；可复现命令与证据见 verification.md。架构取舍见 ADR-006…009。

## P1-01 部分交付（尚未达到完成门槛）

2026-10-02，分支 paco-development，单 Agent；初次交付时未提交/推送，后续按用户明确授权提交本轮改动。没有引擎/镜像安装、VM 启动或 App sandbox 改动。已有 PitchDeck/PitchAssets、iOS scheme 和宣传文档内容保留在工作区，不包含在本轮提交中。

- 目标已固定：Python 3.13.16 独立环境（ADR-012，原 3.13.7 重钉）；Colima 0.10.3 / Lima 2.1.4 / Docker CLI 29.6.2；原生 Linux arm64 OpenCFD OpenFOAM v2506 固定 arm64 digest；原生 Mac arm64 EnergyPlus 26.1.0 / 6f2e40d102，官方资产 SHA-256。选择与官方来源见 ADR-010 和 Backend/Runtime/README.md。
- 已实现：可分发的 runtime manifest、只读/离线/有限超时的真实 doctor、可注入探测、状态/修复提示、架构/版本/身份检查、probe 容器清理、独立 manifest/doctor schema、兼容的 JSON/退出契约和 runtime 检查入口。
- 本机（tanchai，macOS 27.0.1 arm64，16 GiB）：Python 3.13.16 与锁定依赖满足（python_matches=true）；Docker/Colima/Lima/Podman/Multipass 均未安装；EnergyPlus 未发现；environment=blocked。旧机（pacoramirez，32 GiB）曾发现 CLI 但 Colima 未运行。没有任何引擎被声称已验证可执行。
- 验证：doctor 行为测试、Python/Swift/JSON 契约回归与真实本机诊断，命令/结果见 verification.md；模拟 Probe 不作为引擎安装证据。L1/L2/L3 均 not_configured，物理验证 not_performed。
- 阻断：需批准创建/启动 VM 和下载固定镜像/官方 EnergyPlus 包，核实 guest 下载条件；安装后严格 doctor 必须通过并保存真实命令证据，方可完成 P1-01。P1-02 获取独立固定来源的浮力/非等温射流基准；当前无守恒、收敛、精度、性能或数值结果。
