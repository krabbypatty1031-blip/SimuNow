# 实施状态

日期：2026-10-03。当前阶段：**P4 进行中（几何与 case）**。P3 L1 闭环仍在 `dev`。P4-01 已把办公室草稿映射成 L2 房间并写出 OpenFOAM 字典；缺引擎时 `run-l2` 失败且座位温度 omitted。尚未求解、采样、舒适或视口。Mac App 不能当产品 CFD。

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
| P3-01 任务协议 | request/event/result 可解析 | 独立验收 PASS；`TaskProtocolTests`；Python `test_task_protocol`；乱序/截断/错 run 拒绝；无计算按钮 |
| P3-02 本地执行器 | Mac stub worker + JSONL + 取消 | 独立验收 PASS；`TaskExecutorTests`；`stub-task` 不跑 EnergyPlus；失败留目录；日志去掉 `/Users` |
| P3-03 L1 代表日会计 | 冷量/电耗分字段；缺天气 omitted | 独立验收 PASS；`L1AccountingTests`；Python `test_l1_accounting`；`p_elec = q_cool/COP`；`annual_kwh` 永 omitted；request/result 可选天气路径与哈希 |
| P3-04 L2 边界 DTO | 送风 16 不是设定 26；人员显热一次 | 独立验收 PASS；`L2BoundaryTests`；Python `test_boundary`；envelope_u_value omitted |
| P3-05 缓存/超时/恢复 | 同 hash 复用 runID；超时 failed+log | 独立验收 PASS；`TaskExecutorTests` 缓存与超时；`openingPackageIgnoresUnfinishedRun`；freshness 独立 |
| P3-06 真实 L1 | worker `run-l1` 接 EnergyPlus | `test_l1_room` / `test_l1_runner`；缺引擎不填 0；`test/engines` 跑通冷量/电耗 |
| P3-07 占用时段 IDF | Compact 日程，不是 AlwaysOn | `test_l1_schedule`；人数≠座位数；P1 无日程仍 AlwaysOn |
| P3-08 Workspace 提交 | 未配置不可点；「提交代表日 L1」 | `WorkspaceL1Tests`；无「开始计算」 |
| P3-09 沙盒引擎 | 用户选工作副本+引擎；sandbox 保持 | `LocalEngineTests`；书签不进 project.json |
| P3-10 结果与安全 | 电耗/边界；stale；失败不坏稿 | `WorkspaceL1Tests`；年电量显示未知 |
| P3-11 沙盒 App L1 | 包内 WorkerTree + 系统 Python + 用户引擎 | `WorkerStagingTests`；`/usr/bin/python3` doctor；App 资源跑通 `q_cool_w>0`；sandbox 仍 true |
| P3 手测 | 沙盒 Mac 提交办公室代表日 L1 成功 | 冷量 3099.335 W；电功率 1033.112 W = 冷量/COP；全年未知；送风 16 ≠ 设定 26；回风 RET1；新风 0.02 / 回风 0.088 m³/s；新鲜度「当前输入」 |
| P4-01 几何与 case | 草稿→L2 房间；可写 case；缺引擎不编造温度 | `L2RoomMappingTests`；Python `test_l2_room` / `test_l2_runner`；office 送风 16≠26；人数≠座位；`run-l2` failed + `seat_t_c` omitted |
| L0/L3 与场显示接入 | 进行中 | P4-02 起质量；视口仍空 |
| 场渲染/舒适/成本/报告 | 待开发 | P4/P5 |
| RoomPlan/实测/代理/批量 | 待开发 | P6/P7 |

## 下一步

P4 在 `p4-cfd-and-results` 上开工。P4-01 已通过：映射、写 case、缺 OpenFOAM 不编造座位温度。下一步 P4-02 质量门禁，然后才是求解与视口。未推远程。

## P3 阶段结论

阶段门已满足：Mac 改人数/占用时段后可提交不可变代表日 L1；未配置引擎时按钮不可点；失败不把冷量写成 0；一天结果不推全年 kWh。占用时段进入 IDF `Schedule:Compact`，不是 AlwaysOn。沙盒保持开启；worker 从 App 资源拷到容器，用户只选引擎目录。iPhone/iPad 不跑本地 EnergyPlus。围护仍是引擎默认构造。OpenFOAM、三维视口、舒适与报告未做。

## P2 阶段结论

阶段门已满足：契约测试绿；两端共用 `RoomEditorForm`；穿墙与域外座位被拒绝；关闭重开一致；映射含 size/supply/return/window/gains/seats，且不写 `quality.pass`。envelope / 天气 / 求解器仍 omitted。沙盒 App 从编译内嵌 JSON 加载模板，不读仓库 `Fixtures/` 路径。中间视口无三维，属 P4。
