# 实施状态

日期：2026-10-03。当前状态：P0 骨架已验收，P2-01…05 代码已完成；本文件只记录已实现事实，平台显示与物理验证边界见下文。

| 项目 | 状态 | 证据 |
|---|---|---|
| Mac / iOS target、shared schemes | 已创建 | SimuNow.xcodeproj |
| 六个共享模块、空工作区 | 已创建 | Packages/SimuKit |
| draft、run 状态/身份、任务与报告协议 | 已创建 | Core/Simulation/Reporting |
| 未配置引擎实现、worker doctor | 已创建 | UnconfiguredSimulationClient / Backend |
| 计划与 Agent 指南 | 已创建 | Plans / AGENTS.md |
| GitHub 版本管理 | 已绑定 origin/main，提交身份 iampaco | https://github.com/krabbypatty1031-blip/SimuNow |
| 编译/测试/启动 | 验证记录为准 | verification.md |
| P2-01 完整输入模型与契约 | 已完成 | Core/Project、Backend/models、Protocols/project-model-v2.md；verification.md |
| P1-01 固定运行环境与能力检查 | 部分完成，执行验证受阻 | 固定 manifest、真实 doctor、行为/协议测试已实现；Colima 未运行，镜像库存未知，EnergyPlus 未发现；详见下文与 verification.md |
| P2-02 房间向导、门窗与物理参数 | 代码完成 | RoomEditor / ParameterEditing；单位、来源、未知、假设与不确定区间；verification.md |
| P2-03 对象编辑与俯视放置 | 代码完成 | ObjectEditor / RoomPlan；数值与点击放置、引用维护、全部方案几何校验 |
| P2-04 原生项目包与导入 | 代码完成 | DocumentGroup / Documents；原子保存、显式迁移、修复状态、天气附件与哈希 |
| P2-05 模板、基准与快照 | 代码完成 | Templates / Scenarios / WorkspaceStore；完整值撤销、独立候选与不可变快照 |
| L0/L1/L2/L3 引擎 | 待开发 | P1/P3/P4/P7 |
| 场渲染/舒适/成本/报告 | 待开发 | P4/P5 |
| RoomPlan/实测/代理/批量 | 待开发 | P6/P7 |

## 下一步

下一步补齐 P1-01 的真实引擎执行证据，按 P1-02…05 使用有来源的真实输入和基准，不能把人工契约夹具当作物理验证。P2 后续补充 iPhone/iPad 实际显示、最低系统与 VoiceOver 操作检查；P3 再接入真实任务、运行身份与哈希。
不要开始用示意场制作定量推荐。任何阶段完成都要添加 run/命令/验证依据。

## P2-01 完成记录

2026-10-02，开发分支 paco-development：完整项目/场景输入、语义单位与来源、矩形/盒体/单类空调、可组合规则、类型注册、v1 迁移、未知扩展无损保留、不可变场景输入快照及 Workspace/坐标接口已实现。

- 契约：Swift/Python 从共享结构清单生成强类型声明；JSON Schema 2020-12 含分类 payload 约束；生成漂移检查与独立 schema 验证。
- OCP 证据：独立测试模块注册设备并完成项目/快照/规则流程；自定义几何 containment 查询生效，无需修改项目聚合或中央类型分派。
- 验证：`Scripts/check.sh all` 在锁定依赖的独立 Python 环境中通过；Python 14 项、Swift 16 项（含原有 3 项）；2 份人工项目与快照的真实双向交换、28 类错误/兼容性案例；Mac 和 generic iOS Simulator Debug 编译通过。
- 限制：本轮无 UI 编辑、磁盘保存、真实天气/设备数据验证、运行哈希、数值引擎或物理结果；doctor 四级引擎仍为 not_configured。App 本次启动/最低系统运行未验证。
- 日志保存在忽略的 `Artifacts/P2-01/`；可复现命令与证据见 verification.md。架构取舍见 ADR-006…009。

## P1-01 部分交付（尚未达到完成门槛）

2026-10-02，分支 paco-development，单 Agent；初次交付时未提交/推送，后续按用户明确授权提交本轮改动。没有引擎/镜像安装、VM 启动或 App sandbox 改动。已有 PitchDeck/PitchAssets、iOS scheme 和宣传文档内容保留在工作区，不包含在本轮提交中。

- 目标已固定：Python 3.13.7 独立环境；Colima 0.10.3 / Lima 2.1.4 / Docker CLI 29.6.2；原生 Linux arm64 OpenCFD OpenFOAM v2506 固定 arm64 digest；原生 Mac arm64 EnergyPlus 26.1.0 / 6f2e40d102，官方资产 SHA-256。选择与官方来源见 ADR-010 和 Backend/Runtime/README.md。
- 已实现：可分发的 runtime manifest、只读/离线/有限超时的真实 doctor、可注入探测、状态/修复提示、架构/版本/身份检查、probe 容器清理、独立 manifest/doctor schema、兼容的 JSON/退出契约和 runtime 检查入口。
- 实机：macOS 27.0 arm64，物理内存 32 GiB；Backend/.venv 及全部锁定依赖已建立。Docker CLI/Colima/Lima 可发现；Colima 未运行，daemon 不可连接，无 Lima 实例被发现；镜像库存、实际 VM 架构/内存未知；PATH/常见目录未发现原生引擎，EnergyPlus 所选命令未安装。没有任何引擎被声称已验证可执行。
- 验证：doctor 行为测试、Python/Swift/JSON 契约回归与真实本机诊断，命令/结果见 verification.md；模拟 Probe 不作为引擎安装证据。L0/L1/L2/L3 均 not_configured，物理验证 not_performed。
- 阻断：需批准创建/启动 VM 和下载固定镜像/官方 EnergyPlus 包，核实 guest 下载条件；安装后严格 doctor 必须通过并保存真实命令证据，方可完成 P1-01。P1-02 获取独立固定来源的浮力/非等温射流基准；当前无守恒、收敛、精度、性能或数值结果。

## P2-02…05 代码交付（2026-10-03）

按用户授权由四个 Agent 在独立 `codex/p2-02`…`codex/p2-05` worktree 执行规划、实现与自审；根代理整合原生入口、工作区事务、使用条件与最终交叉审查。已有 Pitch、iOS scheme 及其记录保留；实现交付时未提交/推送，后续按用户明确授权提交 P2 改动；未改动计算运行环境。

- P2-02：矩形向导、稳定六面身份、门窗/北向、共享强类型参数表单。未配置围护关系保持缺失，不默认把全部表面当作室外；单位、出处、未知、假设、预设及不确定区间可查看和编辑。
- P2-03：盒体家具、座位/独立采样点/人员、设备热源、单类空调/送回风口/控制与时间表；数值和俯视点击放置，集中米制 Z-up 投影。共享几何变更检查全部方案，维护引用并拒绝新增越界/家具碰撞/实体内点位；未知类型保持只读与原数据。采用 P2 允许的点击与数值降级，未加入拖拽或 3D 手柄。
- P2-04：`.simunow` 目录包、Native DocumentGroup、后台协调读取/独立原子导出、安全作用域、损坏/未来版本拒绝、显式 v1 迁移、不透明附件保留。天气复制到相对资产路径并哈希；格式头检查不等于气象有效性。iOS JSON 导入以独立临时修复会话导出新包。
- P2-05：办公/教室可覆盖布局示例，记录内部假设与模板版本；物理性能、天气、热量、费用不编造。候选独立值、稳定基准 UUID、会话内最近 60 次完整输入撤销/重做及独立输入快照；快照仍非 RunInput。
- 最终审查修复：跨方案同 ID 错误不能互相抵消；重复/悬空/边界冲突条件不被无关编辑静默丢弃，提供显式修复；完整输出参与包预算；过期草稿保留但拒绝提交；对象消失有可关闭状态；天气导入检测并发附件变化；原生包声明符合 package 与 content。
- 验证：Swift 83 项、Python 39 项、2 项目/快照双向交换、28 类语义/兼容案例、App metadata 独立 schema 检查、Mac 与 generic iOS Simulator Debug 构建通过。Mac 模板/方案复制/键盘撤销重做、原生保存关闭及最近项目重开已检查，包内两份 JSON 哈希一致。详见 verification.md。
- 限制：iPad 模拟器安装启动有证据，但 iOS 显示/导入导出交互、真机、最低系统、VoiceOver 实际朗读及多窗口竞争仍未完整验收。设备 v2 没有机身几何，不声明机身碰撞或 CFD patch 法线已验证。引擎、守恒、舒适、能耗和报告状态不变。
