# 实施状态

> 独立 UI 调整（2026-10-03）：ui/plain-language-20261003 从 development 的 959daa7 分出，仅简化界面与信息层次。现有 54 项 Swift 测试、Mac/iOS Debug 构建通过；Mac 已检查建房与设置流程，最后的表单标签/返回按钮调整因锁屏未再截图。原分支未修改，未推送。本节不重新验收下方物理开发阶段。详见 [UI 调整记录](../Execution/UI-plain-language.md)。

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
| P1-01 固定运行环境与能力检查 | 已完成（2026-10-03，strict doctor exit 0 / ready） | runtime/、Artifacts/P1-01/；verification.md P1-01 收尾节；ADR-018 |
| L1/L2/L3 引擎 | L1/L2 引擎已安装并通过最小启动验证（P1-01）；适配器待开发（P1-02…05、P3-03/04） | P1/P3 遗留条件 |
| P5 方案对比/建议卡/基础 PDF | 已完成（L0 口径；舒适与年度费用不含，见计划） | Comparison/、Reporting/；verification.md P5 节 |
| 3D 几何预览 | 已完成（macOS 15+ RealityView；示意桌椅、人体、显示器、门窗和壁挂空调；可在房间内拖动这些物品；更低系统/iOS 回退说明；不含场） | SimuVisualization RoomPreview3D/Layout/Meshes；ADR-017、ADR-020、ADR-021 |
| 场渲染/舒适评价 | 待开发 | P4 |
| RoomPlan/实测/代理/批量 | 待开发 | P6/P7 |
| iOS 模拟器启动 | 已验证（iPhone 17，install+launch+存活） | verification.md「应用启动验证」 |
| Mac App 进程启动 | 已验证（存活 6 秒，无界面交互检查） | verification.md「应用启动验证」 |

## 阻塞项与所需条件（明确记录后继续其他工作）

| 阻塞项 | 影响 | 所需条件 |
|---|---|---|
| P1-01 收尾（引擎环境） | L1/L2 不可用 | 授权：启动 Colima arm64 VM（guest 镜像下载）、拉取固定 OpenFOAM digest（约 340 MB）、下载校验 EnergyPlus 26.1.0（约 210 MB）；strict doctor 通过并留证据 |
| P1-02…05 基准与性能 | P4 前置 | P1-01 完成 + 独立固定的浮力/非等温射流基准来源（镜像不含 tutorials） |
| P4 CFD 与位置级结果 | 舒适评价 | P1 全部 + P3 任务框架（已具备）；当前无任何逐点结果能力 |
| App sandbox 内执行 worker | App 内一键运行 | P7 打包 ADR：受控 helper / companion / 权限例外；当前 DEBUG 无签名构建不受 sandbox 限制，进程级链路已由 LocalSimulationClient 集成测试验证 |
| P6 iOS 采集与校准 | 扫描建模 | 稳定结果管线（已具备）+ LiDAR 设备实机 + 现场测量数据 |
| P7 优化/批量/发布 | 产品化 | 真实案例与误差数据（P6）+ 签名/公证账号 |

GUI 手动演示路径（需用户本机执行）：模板建项目（已含香港大学 10 月气候默认值，朝向默认远侧为正北）→ 计算任务页运行 L0 → 改设定温度看旧结果「待重算」→ 方案对比页生成 ±1 °C 候选并各跑一次 → 查看建议卡 → 报告页导出 PDF。按向导新建的房间仍需填写空调和通风。气候来源见 ADR-019。

## 下一步

P0/P2/P3/P5（L0 口径）与 P1-01 已完成。下一步按依赖顺序：P1-02 公开基准（先浮力后非等温射流，需独立固定来源）→ P1-03 自动 case/网格 → P1-04 EnergyPlus 单区代表日 → P1-05 性能实测 → P3-03 L1 适配器 → P4 CFD。P6/P7 依赖真实案例与现场数据。报告图表增强、费用数据来源是 P5 遗留。
不要开始用示意场制作定量推荐。任何阶段完成都要添加 run/命令/验证依据。

## P1-01 完成记录（2026-10-03，development 分支）

- 安装（全部在 `Backend/RuntimeLocal/`，可一处清理；ADR-018）：colima v0.10.3、limactl 2.1.4（对上游 SHA256SUMS 校验）、docker CLI 29.6.2；arm64 VM（vz，4 核/6 GiB/20 GiB 稀疏盘，研发初始配置）；OpenCFD openfoam-dev v2506 固定 digest 镜像（压缩层 340 MB）；EnergyPlus 26.1.0-6f2e40d102（SHA-256 `7f2ec425…` 匹配 manifest）。
- 真实验证（strict doctor exit 0 / ready）：daemon linux/arm64；镜像 RepoDigests 含固定身份；容器内 `uname -m`=aarch64、`buoyantSimpleFoam -help` 与版本横幅执行成功、版本 2506 匹配、探针容器清理确认；EnergyPlus Mach-O arm64 `--version` 精确匹配版本+build。报告 `Artifacts/P1-01/doctor-strict.json`（schema 校验通过）。
- 执行中修复两个 doctor 真实 bug（v 前缀版本解析、探针递归 source），并修正 manifest `version_command`（镜像不含 foamVersion，改从求解器横幅解析）——详见 ADR-018。
- 限制：最小启动 ≠ 物理验证；P1-02 基准尚未开始；VM 资源配置未实测（P1-05）。引擎目录与 PATH 不污染系统：`source Backend/RuntimeLocal/env.sh` 使用。

## P5 决策与基础报告完成记录（2026-10-03，development 分支）

- 范围：L0 口径的方案对比（有效 run 筛选：completed + 质量通过 + 未过期；同口径分组按 environment+usage 规范文本）、±1 °C 设定温度候选生成、三类建议卡（运行调整/容量配置/舒适改善——舒适卡固定为「需 L2」的状态说明）、费用分层（电价/报价/待报价，不填 0、不外推全年）、CoreGraphics 文本型 PDF 报告（ADR-016）与报告页（无有效 run 时阻止导出并解释）。
- 验证：Swift 49+2 项全部通过（对比筛选/同口径/候选身份/卡片文案含 runID/报告构建/PDF 有效性/空报告阻止导出）；`check.sh all` 退出 0；日志 `Artifacts/P5-check-all.log`。
- 限制：GUI 演示路径（模板 → 补全 → 三方案运行 → 对比 → 导出 PDF）未在本机自动执行，待用户手动验证；Pareto、年度费用、位置级舒适按规则未提供。

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
