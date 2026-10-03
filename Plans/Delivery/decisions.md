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

## ADR-008：沙盒内包 worker、用户只选引擎（已接受）

日期：2026-10-03。
背景：P3 要在 App 里提交真实 L1，但不能默认关闭 sandbox，也不能把开发者 Desktop 路径写进项目。
选择：Mac 把 `simunow_worker` 与 `test/p1` 三个 IDF 脚本打进 Resources/WorkerTree，运行时拷到 Application Support；用户用书签选一次 `test/engines`。iOS 保持 `UnconfiguredL1TaskClient`。不在本阶段做 helper。
影响：本机闭环只在 Mac；EnergyPlus 二进制仍由用户提供，不进 Git。`cs.disable-library-validation` 仅用于加载用户引擎。
验证：`WorkerStagingTests`；沙盒 App 手测办公室 L1 `succeeded`；entitlement 中 sandbox 仍为 true。

## ADR-009：L2 能量门禁计入实测进口面导热（已接受）

日期：2026-10-03。
背景：P4-02 钉版办公室弱射流（带速 0.1 m/s）求解收敛、监测稳定、质量守恒，但能量收支差 23.4%。诊断：fixedValue 进口面在热分层天花板下从近壁单元导热吸热，钉版 run 实测 −305.9 W；P1 大流量（1.2 m/s）下同一机制仅 ~−7 W（能量误差 0.41%），此前可忽略。
备选：(a) 放宽能量门禁——否，门禁是硬约束；(b) 改房间几何让热分层碰不到进口带——否，为过门禁改物理属造假；(c) 把进口面导热实测并计入收支。
选择：(c)。`foam_io` 解析 polyMesh + `writeCellCentres` 的 C 场，`quality.inlet_conduction_w` 逐进口面算 ρcp·(ν/Pr)·A·snGrad，预算 `q_extracted = h_out − h_in − q_inlet_cond`；层流假设被显式守卫（非层流拒绝估算，不猜 0）。计入后能量误差 0.19%，门禁保持 5%。
影响：`test/p1/{run_room,quality,sample_seats,foam_io}.py` 随 P4-02 进库（run-l2 依赖）；弱射流房间整体偏冷约 2.3 K 属该供应模型的真实后果，座位结果随 quality 披露，不包装为实测。湍流模型启用后需补 alphat 边界项再复算。
验证：`test/p1/test_quality.py`（合成 case 手算 −51.0087 W + 2026-10-03 真实数字回归：计入过 / 不计 23% 挂）；钉版 `test_l2_runner` 质量 passed、`quality.json` `terms_w.q_inlet_cond=-305.9`。

## ADR-010：舒适自实现 ISO 7730 附录 D，缺输入 omitted 带原因（已接受）

日期：2026-10-03。
背景：P4-04 要求座位级 PMV/PPD。草稿 schema 无任何舒适输入（无 clo/met/RH/MRT）；`pythermalcomfort` 未安装且按仓库规则不自动引入运行时依赖。
备选：(a) 引入 `pythermalcomfort`——否，新增依赖且沙盒 worker 打包更重；(b) 只做「不可评价」占位——否，输入齐全的调用方（P5+ 草稿假设）应有真实计算；(c) 自实现标准闭式方程。
选择：(c)。`models/comfort.py` 逐行移植 ISO 7730 附录 D 规范性程序（58.15 W/m²·met、分段 fcl、平均迭代 eps 1.5e-4、条件出汗项 0.42(mw−58.15)、hc 两分支取大）；适用域守卫（ta 10–30、tr 10–40、v 0–1、clo 0–2、met 0.8–4、pa ≤ 2700 Pa、PMV ±2）超范围抛 `NotEvaluable`，不猜值。锚点：附录 D 同算法的已发布输出（met 1.4 / clo 0.5 / RH 50：vr 0.22 → PMV 0.17 / PPD 5.6；vr 0.1 → 0.41 / 8.5，逐位复现）与标准 Table 2 / 图 1（PPD(0)=5%、(±0.5)=10%、(±1)=26%）。var 取座位实测风速（久坐无明显肢体运动，不做 met>1 的 Vag 附加）。
影响：`comfortInputs`（mrtC/rhPct/clo/met）为 `evaluate_l2` 上下文新键，runner 暂不传（无来源）→ 指标 `seat_pmv_min/max`、`seat_ppd_max` omitted + `reason` 列出缺失项；契约 metrics 行加可选 `reason`、座位行加可选 `pmv`/`ppd`（schema + Swift + 透传同步）；部分座位超适用域时聚合只覆盖可评座位并在 `reason` 披露排除口径。P5 若给草稿加舒适假设，runner 补传该键即可。
验证：`Backend/tests/test_comfort.py`（算法锚点、Table 2、单调性、六项守卫 + pa/PMV 域、缺/部分/超域座位、evaluate_l2 三态）；钉版 run 重生成 `Fixtures/task/result-l2.json`（座位值与旧 fixture 逐位一致 + 三条舒适 omitted 带 reason）；Python 70 + Swift 94 全绿；mac/ios BUILD SUCCEEDED。

## ADR-011：App 内 L2 走 staged 树与 test/engines 引擎路径，docker 可达性运行时自证（已接受）

日期：2026-10-03。
背景：P4 Goal 要求 Mac 改一个空间参数后提交代表工况 L2。App 沙盒内跑 OpenFOAM 的现实约束：仓库 `test/engines/openfoam.sh` 是 docker 包装（镜像 `simunow/openfoam:2512`），沙盒 App 访问 `/var/run/docker.sock` 与全局 docker CLI 未必可用。
备选：(a) 沙盒内直装 OpenFOAM——版本锁定与打包成本高，P1 验证后再议；(b) 全局关闭 sandbox——违反部署基线；(c) staged 树 + 文件探测 isConfigured，docker 可达性交给运行时，失败即 failed 不编造。
选择：(c)。staged 树扩展为九个 P1 脚本（L1 三件 + L2 六件：`run_room`/`write_openfoam_room`/`quality`/`sample_seats`/`foam_io`/`field_slice`）；`stageEngines` 落位 `runtime/test/engines`（与 `run_room.py` 硬路径 `repo/test/engines/openfoam.sh` 一致）并拷贝 `openfoam.sh`（源缺失时仅 L1 可用）；`LocalProcessL2Client`（macOS）以 `SIMUNOW_ENGINES_ROOT` 指 staged 引擎目录、`workerCommand="run-l2"`、超时 900 s；iOS 保持 `UnconfiguredL2TaskClient`。沙盒内 docker 不可达时 run 失败、座位/舒适指标 omitted，不降级为估算。
影响：`enginesURL(in:)` 语义从 `runtime/engines` 改为 `runtime/test/engines`（L1 probe 仍按 enginesRoot 下 `EnergyPlus/energyplus` 相对解析，行为不变）；`Scripts/generate_project.py` Stage WorkerTree 同步九脚本；App 内首跑 L2 的沙盒 docker 可达性待手测记录，未验证前不宣称 App 内闭环。
验证：`WorkerStagingTests`（六 L2 脚本 staged、engines 落位 test/engines）；`L2ClientTests`（未配置拒绝、wrapper 探测、field-slice 读取/缺文件 nil）；`Backend/tests/test_l2_staged.py` 以 subprocess 重建 staged 树全链路跑 `run-l2`（succeeded + quality passed + field-slice.json 落位，17.7 s）；Python 76 + Swift 113 全绿。

## ADR-012：人员热源以「每人显热」为 L1/L2 对账基准，先披露后对齐（已接受）

日期：2026-10-03（当日以 EnergyPlus 分项输出修正根因）。
背景：单变量实测（`room_p1.json` 唯一改 `n_people` 8→3，两个 IDF 逐行 diff 仅差 People 数，真实 EnergyPlus）发现每人「冷量足迹」≈177.6 W：`q_cool_w` 6334.87→5446.86（−888.02 W），`p_elec_w` 同步 −296.00 W（=−888.02/3），两边 `zone_t` 均 26.0。分项实测（追加 Output:Variable 重跑）：每人 = 显冷 133.3 + 潜冷 44.3 W，其中直接对应人员得热仅 70 W（显 57.0 + 潜 13.0，恰好等于 Activity 表 70 W 全额，守恒闭合）；剩余 ~107.6 W/人是送风为凝结人员湿负荷过冷到更低露点的间接冷量。根因：`write_idf.py` 的 `People` 行把 70 W/人当**活动代谢率**（显热分率由引擎自动定，实测 ≈0.81，IDF 中的 0.3 字面未作为 SHF 生效），而 `L2BoundaryMapping` 把模板 `occupantSensibleW=70` **全额当显热体积源**——office 8 人时 L1 人员显热 456 W vs L2 560 W，L2 温度场虚增 104 W（13 W/人）。违反 AGENTS.md「人员与设备热源在 L1/L2 中同口径」红线的精神：数字分开有注释，但显热份额未真正对齐。
备选：(a) 仅在口径对照表披露、不改数字——否，L2 座位温度场带 392 W 虚增热源，位置级结论失真；(b) 改 L1 让 70 W 变纯显热（SHF=1.0）——否，抹掉人员产湿使 L1 漏算真实潜热/除湿负荷；(c) 把 `occupantSensibleW` 语义定为「每人显热」，L1 的 People 对象按同额显热 + 潜热单列口径写入，L2 保持显热体积源，潜热只进 L1 的 `q_cool` 账。
选择：(c)。实施时点：P4-06 三方案对比之前完成 `write_idf` 人员显热份额与模板值对齐，并重钉 `Fixtures` 与 P3 手测数字；实施前对照表披露该错位，L2 座位结果按「人员源含口径余量」披露。对账规则：跨 L1/L2 的「人员热」对比只以**显热**为基准；`q_cool` 含新风与人员潜热（除湿），不可与 L2 显热收支直接比大小；PMV 所需 RH 由草稿舒适假设单独供给（缺则 omitted，ADR-010），L2 场不解湿度。
影响：`q_cool_w` 语义不变（总冷量含潜热）；对齐后 L2 座位温度将小幅下移（人员源 560→456 W，8 人办公室虚增 104 W），座位结论随之更新，旧 run 标 stale 不复用；`test_l1_schedule`/`L2BoundaryTests` 同步改口径断言。
验证：2026-10-03 单变量实测（8/3 人两 run 目录 `test/outputs/p1_l1/20261003T053325Z`、`20261003T053649Z`；IDF diff 仅 People 数；CSV 日总冷量差 73.54 MJ 与均值口径一致）＋分项实测（追加 Output:Variable 重跑：显冷差 133.3、潜冷差 44.3、People 显 57.0/潜 13.0 W 每人，合计 70 守恒闭合）；对齐实施时补 `write_idf` People 显热断言与双端契约测试。

**实施补录（2026-10-03，对齐已完成）**：模板 `occupantSensibleW` 70→57（office/classroom JSON + `BundledTemplateJSON` 两处，语义=每人显热，实测拆分）；`write_idf.py` 新增 `OCCUPANT_LATENT_W=13`（显式单列，只进 L1 `q_cool`），People 行 activity=显+潜=70 **逐位不变**（SHF 字面 0.3 保留并加 IDF 注释「引擎自行拆分」），L1 IDF 与 P3 手测数字无需重跑；L2 人员显热源 560→456 W（虚增 104 W 消除），钉版重跑 `Fixtures/task/{result,field-slice}-l2.json`（固定 UUID aaaa…/cccc…，inputHash `aa0e6da1…`）：座位温度 **24.43–24.73 °C**（对齐前 25.08–25.39 为 70 W/人全额显热错位口径）、切片 23.35–25.21 °C（24×24 全有效）；断言更新 `test_l1_schedule`（activity 跟随显+潜的敏感性断言 + office activity 70 逐位基线）、`test_boundary`/`test_l2_room`（456 W / 57 W）、`L2BoundaryTests`/`L2RoomMappingTests`/`ContractTests`（57 口径）。Python 78 + Swift 125 全绿；mac/ios BUILD SUCCEEDED。

## 待决定

- P1：OpenFOAM 分支/版本/求解器/网格与湍流，EnergyPlus 版本与设备模型。
- P4：renderer 及各平台预算、舒适档案与边界；L1 事件流式刷新。
- P5：PDF 实现与成本数据；P7：代理/远程/发布渠道。

每条新增决策记录触发原因、备选、选择、影响、验证证据与日期。
