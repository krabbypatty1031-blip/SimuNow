# 工程验证记录

日期：2026-10-03（3D 视口方案 A / UX 用户向界面第一轮 / P5-05 失败路径与离线 PDF / P4 App 手测 C–F / ADR-012 人员显热对齐 / P4-05/P4-06 全量 / P4-04 / P4-02 / P3）/ 2026-10-02（P0–P1）；环境：Apple Silicon Mac、Xcode 27.0 (27A266a)、Xcode Swift 6.4、macOS/iOS SDK27。
工程最低 macOS14/iOS17、Swift6模式；最低系统实机运行尚待验证。手测 App 为 **SimuNowMac Debug**（`SimuNowMacDebug.entitlements` 不含 `app-sandbox`）；Release 仍沙盒，不能把本次 exec 当作沙盒产品闭环。

## 3D 视口方案 A（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，SimuCoreTests 171 + SimuVisualizationTests 23 | 轨道夹紧、切片纹理 axisOrder y/x、失败质量无图、家具计算坐标、`CoordinateMapping` 居中。钉版 10.33112 kWh / 12.397 HKD 未改 |
| `Scripts/check.sh mac` / `ios` | BUILD SUCCEEDED | `#available(macOS 15, iOS 18)` RealityView；旧系统仍编译 Canvas 分支 |
| App Debug 三维手测 | 待用户点 | 拖转、捏合、办公室模板无家具盒、有质量通过场才上色、对比两列同朝向 |

## UX 用户向界面第一轮（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，SimuCoreTests 170 + SimuVisualizationTests 11 | 呈现层、覆盖文案、建议标题、PDF「对比说明」+ 附录哈希。钉版 10.33112 kWh / 12.397 HKD 未改 |
| `Scripts/check.sh mac` / `ios` | BUILD SUCCEEDED | 检查器默认房间/使用/空调；提交在「用电与舒适」；iOS 入口「编辑房间」 |
| App Debug 八条清单 | 待用户点 | 见 [UX-user-facing-ui](../Phases/UX-user-facing-ui/UX-user-facing-ui.md) Task 8 |

## P5-05 离线演示（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，SimuCoreTests 164 + SimuVisualizationTests 10 | 新增 `WorkspaceReportTests` 3 项、`mixedBasisIsExplanationOnlyAndRefusesExport`。无候选不导出；质量失败抛 `notExportable` 且不写文件；办公室两候选无叙述器写出 PDF |
| Python `unittest discover -s Backend/tests` | 通过，116 项 | `test_recommend` 增口径不同 → 只说明、`can_export_recommendation` 为假 |
| `Scripts/check.sh mac` / `ios` | BUILD SUCCEEDED | 报告页有证据才显示「导出证据 PDF」；质量失败只显示说明与状态行；iOS 仍不写 PDF |
| 办公室夹具数字 | 自动化锁定 | 模板 clo=0.5 / met=1.2 / RH 50% / MRT 26 °C；电价 1.2 HKD/kWh「比赛演示假设，非真实电价」。两候选用 P4 手测座位 24.21 / 24.43 °C 与 L1 1033.112 W → 代表日 **10.33112 kWh / 12.397 HKD**。PDF 含两个 run ID、达标比例、HKD、电价声明。状态行「未配置叙述器，仅证据表」 |
| App Debug 点击 L1→L2→固定→导出 | 2026-10-03 已点通 | SimuNowMac Debug + `test/engines`。L1 `B0932281-…`：冷量 3099.335 W / 电功率 1033.112 W。默认口 L2 `057D25D4-…` quality passed，座位 24.43–24.73 °C，PMV 0.16 / PPD 5.95%。误把 z0 写成 2.2（口高 8 cm、风量 0.048）→ `A63B00F4-…` 能量 5.79%>5%，座位 omitted，未固定。改回 z0=2.10–2.28 后再 L2 `373BC329-…` 座位 24.21–24.50 °C，PMV 0.12 / PPD 5.63%。对比两列同口径、共用色标 23.0–25.2 °C。证据 PDF（本地 `test/engines/证据报告.pdf`，不入库）含两 L2 run ID、比例 1、10.3311 kWh / 12.397 HKD、电价声明、舒适四假设、三卡；无叙述器段落、无全年/回收期 |

不得当作产品功能：Release 沙盒 App 内 exec 引擎；叙述器 API 连通；全年电费或回收期；达标比例=实测满意率；质量失败场进有效建议 PDF。

### Debug 手测清单（2026-10-03 已点）

1. [x] 办公室模板。舒适默认与演示电价在「假设与来源」「演示电价」可见。
2. [x] 选 `test/engines`。未配置时 L1/L2 按钮不可点。
3. [x] 提交代表日 L1（先不固定）。提交代表工况 L2（默认口）→ 固定。
4. [x] 改送风口 z0/z1 为 2.10–2.28 m（人数/时段/设定/送风温度不变）→ 再 L2 → 固定。z0=2.2 的失败场未固定。
5. [x] 分析报告页见运行 / 舒适 / 改造三卡；按钮文案是「导出证据 PDF」，不是「生成报告」。
6. [x] 导出 PDF：两个 L2 run ID、达标比例（模型）=1、代表日 12.397 HKD、电价声明。无 `SIMUNOW_REPORT_API_KEY`，状态行「未配置叙述器，仅证据表」。

## P4 App 手测（2026-10-03，办公室模板，引擎 `test/engines`）

| 检查 | 结果 | 说明 |
|---|---|---|
| C 代表日 L1 | `succeeded` | 冷量 3099.335 W，电功率 1033.112 W，全年电量 omitted（一天不推全年）。送风 16 °C ≠ 设定 26 °C |
| D 代表工况 L2（默认送风 z 2.48–2.66 m） | `succeeded` / quality `passed` | 座位 24.43–24.73 °C，最大风速 0.033 m/s，切片 z=1.1 m、576 有效、23.35–25.21 °C；PMV/PPD omitted + `not evaluable: missing mrtC, rhPct, clo, met`。App 数字与钉版 `Fixtures/task/result-l2.json` 及 run `38163E0D-…` 一致 |
| E 改空间参数 | 送风口 **高度** z0/z1 2.48–2.66 → 2.10–2.28 m | 面积/风量/人数/时段/设定/送风温度不变（同口径）。沿墙平移 s0/s1（宽度不变）**不改** `blockMeshDict`：P1 case 把送风口展成整墙条带，沿墙位置不进网格；换墙面 xMin→yMin 同样落到 xmin 进口。高度才改进口带 |
| E 再提交 L2 | `succeeded` / quality `passed` | 座位 **24.21–24.50 °C**（相对基准约 −0.22 K），最大风速 0.030 m/s，切片 23.05–24.96 °C。App 与同口径 CLI `run-l2`（`Artifacts/p4-e-step/run-lowered-supply`，约 20 s）逐位一致 |
| E 方案对比 | 两列并排 | 降低口：24.21–24.50 °C，新鲜度「输入已改」，质量 passed；恢复默认口：24.43–24.73 °C，新鲜度「当前输入」，质量 passed。共用色标 **23.0–25.2 °C**（联合范围，不各自归一化；单列时降低口图例曾是 23.0–25.0）。两列 PMV 均不可评价带同一原因。无「口径不同」警示 |
| 任务页 L1 指标 | 提交 L2 后显示「未知」 | `lastResult` 单槽被 L2 覆盖，L2 无 `q_cool_w`/`p_elec_w`；磁盘 L1 run `FD8C00D1-…` 仍在，未把旧瓦数写成 0 |
| F P4-07B 红斑 L2（默认 nu 0.003 / 24×20×18） | `succeeded` / quality `passed` | 座位 25.16–25.31 °C，PMV 0.29–0.32、PPD ≤7.1%，切片 23.83–26.12 °C（自动色标）。**红斑贴窗**：红色条带紧贴 xMax 墙窗框（窗带 y 2.25–3.75），远窗侧偏蓝；速度箭头/流线正常。App 数字与钉版 `result-l2.json` / `field-slice-l2.json` 及 App 通道重钉 run（`Artifacts/sensitivity/p4-07b/repin/`）一致。等待约 90 s（solve 61 s），900 s 预算内 |

不得当作产品功能：Release 沙盒 App 内 exec EnergyPlus/docker（本次 Debug 关 sandbox，生产路径仍是签名 helper，ADR-011）；「基准 + 两候选」三列（手测固定两列，足以证明并排与共用色标）；沿墙平移风口会改场；任务页同时保留 L1 瓦数与 L2 座位；PMV 有值或实测满意率；稳态切片表示降温时间。

## P4-06 验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，125 项（SimuCoreTests 115 + SimuVisualizationTests 10） | 新增 `CandidateRunTests` 4 项（同口径可比较、人数/时段/设定/送风不同分别阻断并给中文原因、Codable roundtrip 保 draft/切片冻结）与 `WorkspaceComparisonTests` 5 项（pin 冻结几何与口径快照、编辑不改 record、stale 拒绝 pin、共用色标跨候选联合 min/max、混合口径 `basisMismatchText`、质量失败候选 freshness=current 且 slice=nil 与 quality 独立） |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | `WorkspaceView` 对比页（口径警示/共用 yaw 镜头/sharedPalette/runID/哈希/状态/质量/新鲜度并排）、任务页「固定为对比候选」（stale disabled）、`RoomWireframeView` 外部 yaw 与 sharedPalette、`SimulationViewport` 透传 |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | 对比页共用 SimuWorkspace/SimuVisualization 视图；iOS 不接本地 OpenFOAM（L2 按钮仅 macOS） |

不得当作产品功能：对比结论（哪个更舒适）不做自动推荐（P5 建议）。并排显示已于 2026-10-03 Debug 手测记录（见上节）；UI 仍无测试 target，编译与单测不能代替该手测。仓库未预置候选数据。

## ADR-012 人员显热对齐验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| Python `unittest discover -s Backend/tests` | 通过，79 项（约 40s） | 新增/更新断言：`test_l1_schedule`（occupantSensibleW=30 → People activity=43 敏感性、office activity 70 逐位基线）；`test_boundary`/`test_l2_room`（人员显热源 8×57=456 W、`people_w==57`）；`test_project_model`（`project-v2-office.json` fixture 钉 57——ADR-012 漏改第 5 处补钉，防再漂移）；钉版 `test_l2_runner`/`test_field_slice` 为独立复算型断言，随新钉版自动自洽 |
| `Scripts/check.sh test` | 通过，125 项（SimuCoreTests 115 + SimuVisualizationTests 10） | 更新断言：`L2BoundaryTests`（8×57、occupantTotal 456）、`L2RoomMappingTests`（3×57）、`ContractTests`（模板 occupantSensibleW 57）；`BundledTemplateJSON` office/classroom 两处 57.0 |
| 钉版重跑 | 真实收敛场 | `run-l2` 固定 UUID 重跑（对齐后口径）：`Fixtures/task/result-l2.json` 座位 tC 24.42899–24.72772 °C（对齐前 25.08–25.39，下移 ~0.65 K，虚增 104 W 消除）；`field-slice-l2.json` 23.34831–25.20712 °C、576 全有效；result.identity.inputHash `aa0e6da1…`（草稿快照哈希），切片 inputHash `c922cf7a…`（P1 房间哈希），两层语义，钉版 match: False 为预期 |
| L1 逐位不变 | 逐行 diff 证据 | People 行 activity = 57+13=70 与对齐前逐位一致（SHF 字面 0.3 保留，引擎自行拆分）→ L1 IDF 与 P3 手测数字（`q_cool` 6334.87）无需重钉 |
| `Scripts/check.sh mac` / `ios` | BUILD SUCCEEDED | 模板 JSON 数值变化不影响 App 编译；`generate_project.py` 无需改动（包内源码与资源） |

不得当作产品功能：ADR-012 消除的是 L1/L2 人员显热口径错位（70 全额显热 vs 实测 57 显 + 13 潜），不代表座位温度有任何实测标定；切片与座位数字仍为钉版真实求解值。App 内重跑已于 2026-10-03 Debug 手测记录（见上节）；Release 沙盒未验证。

## P4-05 全量验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，107 项（SimuCoreTests 97 + SimuVisualizationTests 10；另含 App 内 L2 接线新增 6 项共 113，再含 `WorkspaceL2Tests` 3 项共 116） | P4-05 b/c 新增：`FieldSliceTests` 3 项（fixture 解码；wire claim 变体 unit K / axisOrder ["x","y"] / interpolated / leftHandedYUp / failed 与 shape 不匹配均拒绝）；`SlicePaletteTests` 3 项（hue 单调蓝→红、clamp 不外推、图例带物理范围与 °C、退化范围单色）；`RoomSceneTests` 7 项（P4-05a） |
| Python `unittest discover -s Backend/tests` | 通过，75 项（约 21.8s；另含接线新增 `test_l2_staged` 1 项共 76，约 38s） | P4-05 b/c 新增 `test_field_slice` 5 项（合成 2 单元场掩码/统计/契约字段、z 越界与 spacing≤0 拒绝、quality False 不写文件）；钉版 `test_l2_runner` 追加 576 格点独立复算（格点→foam_xyz→最近单元 T == payload 值，9 位小数；stats 与 values 一致；validCount == 掩码计数） |
| 钉版切片数值 | 真实收敛场 | `Fixtures/task/field-slice-l2.json`（ADR-012 重钉后）：24×24 格心 @z=1.1 m、576 全有效、23.348–25.207 °C（对齐前 23.938–25.876 为 70 W/人全额显热口径）、inputHash = P1 房间输入哈希（`c922cf7a…`，与 result.identity.inputHash 是两个语义层，切片哈希与 quality.json/samples.json 同源） |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | `FieldSlice`/`SlicePalette`/`RoomWireframeView` 切片叠加与图例；`generate_project.py` Stage WorkerTree 扩为九个 P1 脚本 |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | `SimuVisualization` 无 macOS 专属 API；iOS 不接本地 OpenFOAM |

不得当作产品功能：切片只随质量通过的 run 出现（quality_pass False 不写文件、视口无 field 不填色）；切片 inputHash 是 P1 房间输入哈希不是草稿快照哈希；切片密度（0.25 m 提示）不进座位数字（座位仍钉最近单元）。App 内 L2 提交接线（ADR-011）单测见上表。**Debug 手测**已于 2026-10-03 记录（办公室 L2 质量 passed + 切片）；Release 沙盒仍不能 exec 用户选定 EnergyPlus/docker（ADR-011 第七段），不宣称沙盒产品闭环。

## P4-04 全量验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，94 项 | `L2ResultTests` 新增：舒适指标 omitted + `reason`（含 mrtC/rhPct）、座位无 `pmv`；`result-l1.json` 向后兼容不变 |
| Python `unittest discover -s Backend/tests` | 通过，70 项（约 21.3s） | 含 `test_comfort` 11 项与钉版 `test_l2_runner` 全管线 |
| `Backend.tests.test_comfort` | 通过，11 项 | 附录 D 同算法已发布输出逐位复现（met1.4/clo0.5/RH50：vr0.22→PMV 0.17/PPD 5.6；vr0.1→0.41/8.5）；Table 2 PPD（0→5.0、±0.5→10.2、±1→26.1）；温度单调；ta/tr/v/clo/met/rh/pa/PMV 适用域守卫；缺/部分/超域座位与 `evaluate_l2` 三态 |
| `Fixtures/task/result-l2.json` | 钉版重生成 | 真实 run 重跑：座位值与旧 fixture 逐位一致（25.0796/25.3862/0.0338…，确定性验证）；新增三条舒适指标 omitted + `reason: not evaluable: missing mrtC, rhPct, clo, met (comfort inputs not modeled)`；inputHash 不变 |
| `test_task_protocol` 透传 | 通过 | `parse_result` 不丢 `reason`；座位不出现 `pmv` 键 |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | `ResultMetric.reason` 与 `SeatSample.pmv/ppd` 加可选字段后兼容 |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | 同上 |

不得当作产品功能：当前草稿无舒适输入来源，PMV 恒为 omitted + 原因（P5+ 草稿假设接入后才有值）；PMV 是模型判据不是实测满意率；var 取座位实测风速，久坐未做 met>1 的 Vag 附加（ADR-010）。

## P4-02 全量验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，93 项 | 含 `L2ResultTests`：门禁缺项不通过、`allGatesPass` 镜像 Python、`result-l2.json` 解码、`result-l1.json` 向后兼容 |
| Python `unittest discover -s Backend/tests` | 通过，55 项（约 20.6s） | 含钉版 `test_l2_runner` 全管线：state succeeded、quality passed、`checkMesh ok`、`monitorsStable`、座位 tC>15、`seat_t_c_min` 非 omitted |
| `python3 test/p1/test_quality.py` | 通过，5 项 | 进口面导热合成 case 手算 −51.0087 W；湍流/计数不匹配/缺 patch 拒绝；2026-10-03 弱射流回归：计入过、不计 23% 挂 |
| `python3 test/p1/test_room.py` | 通过，8 项 | 预算新必填 `q_inlet_cond_w` 后全绿 |
| 钉版 L2 管线数值 | quality passed | 质量相对误差 2.35e-6；能量相对误差 **0.19%**（计入门禁前假象 23.4%）；`terms_w.q_inlet_cond = −305.9 W`；座位（ADR-012 对齐后重钉）24.42899 / 24.43970 / 24.72772 / 24.71752 °C，uMag 0.0259–0.0333 m/s 全带 `lowSpeedAbsoluteError` |
| P4-03 座位采样 | 通过 | `Backend.tests.test_l2_sampling` 3 项（合成场）；钉版 `test_l2_runner` 追加最近单元温度复算；证据 run：域外座位 omitted（`reason: not_in_fluid`），4 有效座位采样，state succeeded / quality passed |
| `Fixtures/task/result-l2.json` | 钉版真值 | 固定 UUID（aaaa…/cccc…）；真实收敛场数值，非手编 |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | `SimulationResult` 加可选 `qualityDetail`/`seatSamples` 后两端编译兼容 |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | 同上 |

不得当作产品功能：稳态场不推降温时间；座位温度是模型值非实测满意率；进口面导热使弱射流房间偏冷约 2.3 K，属该供应模型后果；带缩放（送风/窗）为整墙跨度假设。

## P3 全量验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，85 项 | 协议、stub、真实 L1、Workspace 提交、WorkerTree 暂存 |
| Python `unittest discover -s Backend/tests` | 通过，37 项 | 含 `test_task_protocol` / `test_l1_runner` / `test_l1_schedule` / `test_python39_worker` |
| `python3 -m simunow_worker doctor` | 通过探测 | 系统 Python 3.9 可启动；无引擎时不编造瓦特 |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | sandbox 仍为 true；Mac 有 Stage WorkerTree |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | 无 `LocalProcessClient` / `Process` |
| 计算按钮 | 无 | 文案是「提交代表日 L1」；未配置时不可点 |
| App 手测 | 办公室 L1 `succeeded` | 冷量 3099.335 W，电功率 1033.112 W，全年未知 |
| P3 清单 | 01–11 已勾选 | 闭环只覆盖代表日 L1，不是 CFD |

不得当作产品功能：缓存仅进程内存；取消是 `terminate()` 不是进程树；一天不能推全年；围护是引擎默认；不是逐点 CFD。

## 最终目录验证结果

验证从 `/Users/pacoramirez/Desktop/SimuNow` 执行，确认本地包和文件使用相对路径，工程可搬移。

| 检查 | 结果 | 说明 |
|---|---|---|
| pbxproj 语法与共享 scheme XML | 通过 | plutil 与 XML 解析 |
| Swift Package 测试 | 通过，3项 | draft round-trip、旧 run 新鲜度、未配置引擎拒绝成功 |
| SimuNowMac Debug | BUILD SUCCEEDED | 当前 Apple Silicon 架构，关闭签名构建 |
| SimuNowiOS Debug | BUILD SUCCEEDED | generic iOS Simulator，不需要开发团队 |
| Mac 启动与界面 | 通过 | 空工作区、sidebar、inspector、报告空状态可见 |
| Xcode 打开工程 | 通过 | 两端 shared schemes 与本地包可见 |
| 文档本地链接 | 通过 | 21份计划文档，无失效相对链接 |
| Python doctor | 通过 | worker 正常；P1-01 起在 `SIMUNOW_ENGINES_ROOT` 下 L1/L2 为 configured |
| OpenFOAM P1-02 基准 | 通过 | `test/p1/run_benchmarks.py`；方腔 Nu=2.260 vs 2.243；射流 Um/U0=0.781 vs 0.783；**本条只证明浮力与能量扩散离散，不能证明送风射流、短路或座位分层** |
| P1-03 房间管线 | 通过 | `SIMUNOW_ENGINES_ROOT=test/engines python3 test/p1/run_room.py --input test/p1/fixtures/room_p1.json`；run `20261002T135352Z`/`20261002T135415Z`；`quality.pass=true`；质量 ~0、能量 0.41%；复算座位 ΔT=0 |
| P1-04 EnergyPlus 代表日 | 通过 | `python3 test/p1/run_l1.py --input test/p1/fixtures/room_p1.json`；run `20261002T134747Z`；`EnergyPlus Completed Successfully`；冷量 6334.87 W，电耗=冷量/3；无年节能量 |
| P1-05 粗/中网格 | 通过 | `python3 test/p1/mesh_study.py`；粗 2.9s / 16.0 MB，中 14.3s / 19.8 MB；未做第三套网格 |
| iOS实际启动/真机/最低系统 | 未验证 | 编译通过不等于设备运行验证 |

最终构建命令：`Scripts/check.sh all`。共享包使用 Swift Testing，日志中的 XCTest 0项不代表未测试；后续 Swift Testing 输出确认3项通过。
Mac 观察显示报告空状态的三栏布局，未展示任何数值结果。用户可在 Xcode 选择 SimuNowMac / My Mac 运行。
构建中的 AppIntents metadata 未抽取提示属于当前没有依赖 AppIntents 的说明，不阻断构建。

## 验证范围

项目结构、共享包契约、macOS Debug 和 generic iOS Simulator 编译、worker 能力探测、P1-01…P1-05 命令行物理验证。
P1 不能当作扫描、舒适 PMV、App 切片或定量方案推荐已完成。网格只有粗/中两套，不能声称网格无关。

## 环境处理

系统命令行默认 CommandLineTools；脚本显式设置 DEVELOPER_DIR，不修改全局选择。
Desktop/Documents 的 File Provider 属性可影响测试 bundle 签名，因此脚本默认使用临时构建目录。
Debug 设置 ONLY_ACTIVE_ARCH=YES，保持 App 与本地包架构一致；Release 仍使用默认多架构设置。
