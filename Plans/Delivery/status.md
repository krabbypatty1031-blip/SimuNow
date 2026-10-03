# 实施状态

日期：2026-10-03。当前阶段：**P2 房间编辑通过**（内存编辑、项目包、模板与 P1 映射）。P1 物理验证仍只在 CLI。Mac App 不能当产品 CFD 或定量推荐。

| 项目 | 状态 | 证据 |
|---|---|---|
| Mac / iOS target、shared schemes | 已创建 | SimuNow.xcodeproj |
| 六个共享模块、空工作区 | 已创建 | Packages/SimuKit |
| draft、run 状态/身份、任务与报告协议 | 已创建 | Core/Simulation/Reporting |
| 未配置引擎实现、worker doctor | 已创建；P1-01 起 L1/L2 可探测 | UnconfiguredSimulationClient / Backend doctor |
| OpenFOAM 公开基准（P1-02） | 已跑方腔 Nu 与平面射流 Um/U0 | `test/outputs/p1_bench/bench_report.json`。本条只证明浮力与能量扩散离散，不能证明送风射流、短路或座位分层 |
| P1-03 参数房间管线 | 质量通过且可复算 | `test/outputs/p1_room/20261002T135352Z` 与 `20261002T135415Z`；`quality.pass=true`；质量相对误差 ~0；能量相对误差 0.41%；`test/outputs/p1_room/repro.json` 两次 `input_hash` 相同、座位 ΔT=0 |
| P1-04 单区 EnergyPlus 代表日 | 已跑通 | `test/outputs/p1_l1/20261002T134747Z`；`EnergyPlus Completed Successfully`；`q_cool_w=6334.87`；`p_elec_w=2111.62=q_cool/COP`；`model: equivalent_ideal_loads`；窗 L1 1314 W vs L2 624 W（口径不同，已写对照表） |
| P1-05 粗/中网格 | 已测 | `test/outputs/p1_mesh/perf_table.md`：粗 2.9s / 16.0 MB，中 14.3s / 19.8 MB。未做第三套网格，不能声称网格无关 |
| 计划与 Agent 指南 | 已创建 | Plans / AGENTS.md |
| GitHub 版本管理 | 已绑定 origin/main，提交身份 iampaco | https://github.com/krabbypatty1031-blip/SimuNow |
| 编译/测试/启动 | 验证记录为准 | verification.md |
| P2-01 项目模型 | 已冻结 v2 三分区；开口有墙面跨度 | `Scripts/check.sh test`；Python `test_project_model` |
| P2-02 房间编辑表单 | 尺寸/门窗/朝向/假设可写内存模型；无计算按钮 | 独立验收 PASS；`Scripts/check.sh test`；`RoomEditorForm` 两端共用 |
| P2-03 放置校验 | 家具/座位/送回风口可数值编辑；风量互校；坐标映射 | 独立验收 PASS；`PlacementTests`；ADR-006 本阶段不撤销；`Scripts/check.sh mac` / `ios` BUILD SUCCEEDED |
| P2-04 项目包 | 原子保存/导入 `.simunow/project.json` | 独立验收 PASS；`PackageTests`；ADR-007 目录包 |
| P2-05 模板与 P1 映射 | 办公/教室模板、基准快照、只读 P1 字段 | 独立验收 PASS；`TemplateTests`；Python `test_p1_mapping`；窗面积 1.95 不是墙宽 |
| P2 手测 | 沙盒内从内嵌模板创建；尺寸刷新；方案对比 | 办公室 6×6×2.8；改长度后对比页基准 6 / 当前 7；视口仍为空状态 |
| P2 房间编辑 | 阶段门已满足；仍未接求解器 | 见下方阶段结论 |
| L0/L3 与 App 接入 | 待开发 | P3/P4/P7 |
| 场渲染/舒适/成本/报告 | 待开发 | P4/P5 |
| RoomPlan/实测/代理/批量 | 待开发 | P6/P7 |

## 下一步

P3 任务协议与引擎接入。人数/显热/设定温度仍无独立表单。P1 映射是只读 DTO，不是可提交的 `room_p1.json`。不要用示意场做定量推荐。未完成计算接入时，界面不得出现可点的「开始计算 / 导出报告」。

## P2 阶段结论

阶段门已满足：契约测试绿；两端共用 `RoomEditorForm`；穿墙与域外座位被拒绝；关闭重开一致；映射含 size/supply/return/window/gains/seats，且不写 `quality.pass`。envelope / 天气 / 求解器仍 omitted。沙盒 App 从编译内嵌 JSON 加载模板，不读仓库 `Fixtures/` 路径。中间视口无三维，属 P4。
