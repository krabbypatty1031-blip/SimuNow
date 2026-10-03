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

- [ ] P4-03a 座位在流体域，坐姿高度
- [ ] P4-03b 墙/家具内样点拒绝；不把实体 0 当室温

## P4-04 舒适

- [ ] P4-04a 输入够才评 PMV/PPD
- [ ] P4-04b 缺湿/辐射/衣着或超范围 → 不可评价

## P4-05 视口与场

- [ ] P4-05a 房间盒子/开口/风口/座位几何，不是空状态
- [ ] P4-05b 场文件带单位、Z-up、有效掩码
- [ ] P4-05c 有结果后叠温度切片；无场不画假彩色

## P4-06 候选对比

- [ ] P4-06a 基准 + 两候选同口径
- [ ] P4-06b 共用色标；stale / quality 分开
