# P4 可验收清单

> 给执行者：按 `P4-01` → `P4-06` 顺序。勾选后把命令与证据写入 `Plans/Delivery/status.md`。

**Goal:** Mac 改一个空间参数后能提交代表工况 L2，看到质量状态、座位指标和温度切片；失败场不能当有效评价。本阶段不把 L0 平均或假彩色包装成 CFD，不做费用/建议/PDF。

**已有、不得再当 P4 完成证据：** P1 CLI 房间算例与质量脚本；P2 房间编辑；P3 代表日 L1 与 L2 边界 DTO；空的 `SimulationViewport`。

**锁定（P4 全程沿用）：**

- 任务 JSON camelCase，CodingKeys 显式
- 设定温度 ≠ 送风温度；循环回风 ≠ 室外新风
- 人员显热按人数计一次；座位是采样点，不是第二热源
- 不发明围护 UA / 墙面温度；缺则 omitted
- 质量失败、未收敛、实体内采样不得写成有效场
- 缺失舒适输入标不可评价，不填 0
- 稳态动画不表示降温时间；一天结果不推全年
- 两方案共用镜头和色标
- iOS 不接本地 OpenFOAM；Mac sandbox 不以关闭沙盒为修复
- 未配置引擎时不可点提交；配置后文案为「提交代表工况 L2」，不是「开始计算」

## P4-01 几何与 case

- [x] P4-01a 草稿 + 边界 → L2 房间 JSON；送风 T 不是设定 T
- [x] P4-01b 写出 OpenFOAM case（blockMesh 字典），不求解
- [x] P4-01c 改人数或送风速度后 input_hash 变；缺引擎不编造温度（求解器尚未接线）

## P4-02 质量

- [x] P4-02a quality.json：checkMesh / 残差 / 监测 / 质量 / 能量（能量收支含实测进口面导热项；P1 脚本 `test/p1/{run_room,quality,sample_seats,foam_io}.py` 进库）
- [x] P4-02b 失败不可当有效结果；不把 0 当通过（quality 三轴独立：state / quality / seatSamples；`Fixtures/task/result-l2.json` 为钉版真实 run）

## P4-03 采样

- [x] P4-03a 座位在流体域，坐姿高度（`sample_seats` 逐座位核算：有效座位从求解网格最近单元采样；域外座位 omitted + reason，不编造；sampled + omitted = 座位数，静默丢失即失败）
- [x] P4-03b 墙/家具内样点拒绝；不把实体 0 当室温（墙外=域外→omitted；家具在 L2 房间未建模，assumptions 已记 omitted；钉版测试从 case 终场独立复算最近单元温度 == samples.json 值，显示切片密度不进座位数字）

## P4-04 舒适

- [x] P4-04a 输入够才评 PMV/PPD（自实现 ISO 7730 附录 D 程序，ADR-010；`comfortInputs` 齐全且在适用域内才逐座位评 `pmv`/`ppd` + 聚合 `seat_pmv_min/max`、`seat_ppd_max`，method `iso7730_pmv`；锚点复现附录 D 同算法已发布输出 0.17/5.6 与 0.41/8.5）
- [x] P4-04b 缺湿/辐射/衣着或超范围 → 不可评价（缺 MRT/RH/clo/met 任一项或座位值超适用域 → 指标 omitted + `reason` 列出缺失项/排除口径；不填 PMV=0；部分超域聚合只覆盖可评座位并在 reason 披露）

## P4-05 视口与场

- [x] P4-05a 房间盒子/开口/风口/座位几何，不是空状态（`RoomScene(draft:)` 无 geometry → nil → 空状态不画假房间；`RoomWireframeView` Canvas 线框 + 可拖拽 yaw；`IsometricProjection` 消费 `CoordinateMapping`（Z-up→Y-up→屏幕），无第二坐标约定；`SimuVisualizationTests` 7 项；Workspace 视口换新 API）
- [x] P4-05b 场文件带单位、Z-up、有效掩码（`test/p1/field_slice.py` 写 `field-slice.json`：kind temperature_slice、unit C、coordinateSystem rightHandedZUp、axisOrder ["y","x"]、sampleMethod nearest_cell、valid 掩码与 stats 只算有效格；`Protocols/Schemas/field-slice.schema.json` 钉死 wire claim；Swift `FieldSlice` 严格解码拒绝变体；脚本进库（.gitignore 白名单））
- [x] P4-05c 有结果后叠温度切片；无场不画假彩色（quality_pass False → 不写文件 → 视口无 field；`SlicePalette` 不外推 clamp、invalid 格中性灰；`RoomWireframeView` 画切片 + 底部渐变图例带物理范围；`SimulationViewport(draft:field:)`；钉版 `Fixtures/task/field-slice-l2.json` 24×24 全有效 23.826–26.124 °C（P4-07B 重钉；P4-07A 时 23.376–25.448），`test_l2_runner` 576 格点独立复算）
- [x] P4-05d App 内提交代表工况 L2（ADR-011：staged 树十个 P1 脚本 + 引擎落位 `runtime/test/engines` 并拷 `openfoam.sh`；`L2TaskClient`/`LocalProcessL2Client`（`run-l2`、`SIMUNOW_ENGINES_ROOT`、超时 900 s、`loadFieldSlice` / `loadFlowOverlay` 质量门控）；`WorkspaceStore.submitL2()`/`canSubmitL2`/`lastFieldSlice`（质量失败 → 指标 omitted + 无切片不编造）；按钮文案「提交代表工况 L2」未配置不可点；iOS 保持未配置客户端；视口传 `store.lastFieldSlice`）
- [x] P4-05e 质量通过才叠稳态速度箭头与流线（`field_flow.py` 写 `field-flow.json`；失败不写文件；箭头长度是显示放大；不是开机降温动画）

## P4-06 候选对比

- [x] P4-06a 基准 + 两候选同口径（`CandidateRun` 冻结快照（identity/metrics/slice/basis/draft），stale 拒绝固定；`basisMismatch` 口径守卫——人数/占用时段/设定/送风不同 → 警示「并排数值不是有效比较」，不静默并排）
- [x] P4-06b 共用色标；stale / quality 分开（页级共用 yaw 镜头；`comparisonPaletteRange` 联合范围 `sharedPalette` 传每个候选视口；`candidateFreshness` 与 quality 并排独立显示；`CandidateRunTests` 4 项 + `WorkspaceComparisonTests` 5 项）

## P4-07 窗几何保真：换墙、多窗、出红斑（[P4-07](P4-07-window-geometry.md)，A、B 均已实施）

- [x] P4-07A-a 房间 JSON `window` → `windows[]`（`l2_room.py` 逐窗 wall/s0/s1/z0/z1/q 投影；同墙重叠合并成包围盒 q = ΣW/A 守恒；xMin 窗撞送/回风带 ValueError；`p1_mapping.py`/`room_input.py` 双形状，legacy L1 单窗逐位不变）
- [x] P4-07A-b case writer 三向切分多块网格（`write_openfoam_room.py` cuts_x/cuts_h/cuts_s；逐窗 `windowN` patch 各自 fixedGradient q_i/kappa；`frontAndBack` 并入 `walls`；`case_meta.json` 带 windows[]；单窗满跨与旧版同构 21 块/ΣW 156 W）
- [x] P4-07A-c 能量门改 Σ 逐窗 q×A 对账（`run_room.py` `q_window_w=window_total_w` + legacy 无 windows[] 即 RoomError；`write_idf.py` 双形状钉版逐位不变 + 修 ADR-012 遗留人员 8×57=456 断言；办公室/挪窗/换墙三引擎 run 质量全过，mass 1.97e-6、energy 0.38%）
- [x] P4-07A-d 挪窗/换墙敏感性存证（`Artifacts/sensitivity/p4-07-{repin,move,wall}/` 本地：暖区随窗移动 (y=2.88→0.62)、换墙到 yMax 暖区 (y=5.62)；钉版重钉 8 座位 24.42–24.71 °C / PMV 0.16–0.21、切片 23.376–25.448 °C + 迁移说明；`L2ResultTests` 8 座位 + 舒适变异测试；View/图例文案改逐窗口径）
- [x] P4-07B 网格 + 粘度阶梯（`Artifacts/sensitivity/p4-07b/` 本地六档 nu{0.006,0.003,0.0015}×mesh{16×12×14,24×20×18} **全过五门禁**；采纳 nu 0.003 + 24×20×18：切片 max 贴窗 0.12 m、26.34 °C（0.006 时 25.45–25.91）；0.0015 虽全过但近/远窗座位温差在粗细网格变号（−0.12 vs +0.00 K），座位级结果网格敏感故不取，停在 0.003 如实披露；`l2_room.py` 默认 + assumptions + `room_p1.json` 同步；钉版再重钉 8 座位 25.16–25.31 °C / PMV 0.29–0.32 / 切片 23.83–26.12 °C；solve 61 s 在 App 900 s 预算内，`l2_runner` 600 s 不动）

## 手测（2026-10-03，SimuNowMac Debug）

- [x] 办公室 L1 / 默认口 L2 / 改送风口高度再 L2 / 两列对比（数字与限制见 `Plans/Delivery/verification.md`「P4 App 手测」；Release 沙盒未验证）
- [x] P4-07B 红斑 App 手测（默认 nu 0.003 / 24×20×18：quality passed，座位 25.16–25.31 °C、PMV 0.29–0.32，切片 23.83–26.12 °C 自动色标下**红斑紧贴窗框**、远窗侧偏蓝；数字与钉版一致；见 verification.md「P4 App 手测」F 行）
