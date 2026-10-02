# 实施状态

日期：2026-10-02。当前阶段：**P1 物理验证通过**（五条阶段门均有 run 证据）；本文件只记录已实现事实。Mac App 仍是空工作区，不能当产品验证或定量推荐。

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
| 房间编辑/保存/导入 | 待开发 P2 | P2-01…05 |
| L0/L3 与 App 接入 | 待开发 | P3/P4/P7 |
| 场渲染/舒适/成本/报告 | 待开发 | P4/P5 |
| RoomPlan/实测/代理/批量 | 待开发 | P6/P7 |

## 下一步

P2-01 冻结完整房间模型。不要开始用示意场或本阶段座位 ΔT 制作定量推荐。任何阶段完成都要添加 run/命令/验证依据。
