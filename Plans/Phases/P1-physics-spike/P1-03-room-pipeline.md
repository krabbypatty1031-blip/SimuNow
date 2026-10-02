# P1-03 参数房间管线

**Files:**

- Create: `test/p1/room_schema.json`
- Create: `test/p1/write_openfoam_room.py`（可从 `test/p0/export_openfoam.py` 升级到 v2512：`p`、`alphat`、无 `#includeFunc residuals`）
- Create: `test/p1/run_room.py`
- Create: `test/p1/quality.py`（质量/能量，控制体积分，不用短循环回风当混合杯）
- Create: `test/p1/sample_seats.py`
- Fixture: 以 `test/fixtures/room_split_ac.json` 为起点冻结一份 `test/p1/fixtures/room_p1.json`
- Evidence: `test/outputs/p1_room/<utc>/`（input.json、case、checkMesh.log、solver.log、quality.json、samples.json、slices）

**Interfaces:**

- Consumes: P1-01 镜像；P1-04 若已有墙温/热流则用，否则房间第一版允许窗用给定 `q_w_m2`，但必须在 `assumptions` 标明
- Produces: `quality.json`、`samples.json`（座位 x,y,z,T_C,U_mag）、`input_hash`

坐标（必须写进 `room_p1.json` 的 `coordinates` 字段）：

- 对外契约：米制、右手、**Z-up**（与 `AGENTS.md` 一致）
- OpenFOAM case 内允许 Y-up，但 adapter 必须记录 `foam_up_axis` 与重力向量；采样输出转回 Z-up °C

重力：`(0, 0, -9.81)` 在契约坐标；写入 OF 时随 `foam_up_axis` 转换。

---

### P1-03a 冻结输入

- [x] `room_p1.json` 含：房间尺寸、送回风口几何、送风 T 与速度、人数热源、窗热流或 L1 面温、座位高度与平面位置
- [x] 每个不确定值保留 value / unit / source（来源至少 `assumed` 或 `fixture`）
- [x] SHA-256 规范化后作为 `input_hash`（排除相机等展示字段）
- [x] 第一版允许无家具盒体，须在 `assumptions` 写 `omitted: furniture_boxes`；加上阻塞体积后须重算 input_hash

通过：两份文件排序后哈希稳定。失败：同一 JSON 两次哈希不同。

### P1-03b 写 case

- [x] 生成 `0/U` `0/T` `0/p_rgh` `0/p` `0/alphat`、`constant/{g,transportProperties|physicalProperties,momentumTransport}`、`system/{blockMeshDict,controlDict,fvSchemes,fvSolution}`
- [x] `controlDict.application` = `buoyantBoussinesqSimpleFoam`
- [x] 送风 patch 独立于回风；循环风与新风不混成一个边界

通过：目录可被 `test/engines/openfoam.sh <case> blockMesh` 读取。失败：缺 `alphat`、或 case 落在 `$HOME` 而非 `-case`。

### P1-03c 网格门禁

- [x] `blockMesh` 退出码 0
- [x] `checkMesh` 无负体积；非正交/web 错误按 OpenFOAM `Failed` 则本任务失败
- [x] 日志拷贝进 run 目录

通过：`quality.json` 含 `"checkMesh": "ok"`。失败：忽略 Failed 继续求解。

### P1-03d 求解与监测

- [x] 监测：回风平均 T、远座 T、送风速度
- [x] 停止条件：达到 `endTime` **或** residualControl，且最后 N 步监测点变化低于任务里写明的阈值（阈值写入 `quality.json`，不得事后改）
- [x] 残差下降不能单独判通过

通过：`solver.log` 有 `End` 且监测序列在 run 目录。失败：发散仍标 success。

### P1-03e 采样与切片

- [x] 座位样点在流体域（不在家具/墙内）
- [x] 输出 T[°C]、速度大小；近零速度同时给绝对误差备注位
- [x] 至少一张水平切片（坐姿高度，默认夹具 `seat_height_m=1.1`）
- [x] PyVista 若未装：允许先用 `postProcess`/`sample` 字典导出 VTK/CSV，但报告写明「未用 PyVista」；P1 验收不因缺 3D 窗失败，但必须有文件

通过：`samples.json` 点数 = 座位数。失败：用实体内 0 值当室温。

### P1-03f 守恒

- [x] 质量：送风质量流 − 回风质量流，相对误差 &lt; 1%
- [x] 能量：送风焓 + 壁面/人体/窗热源 − 回风焓，相对误差 &lt; 5%
- [x] 分母与各项 W 写进 `quality.json`；禁止用混合杯 `m*cp*(T_return−T_supply)` 在短路时当唯一判据（P0 已证明会假失败）

通过：两项都过，或明确 `fail` 且脚本退出码非 0。失败：质量失败仍给有效场。

### P1-03g 可复算

- [x] 删除结果后用同一 `input_hash` 再跑
- [x] 座位 T 差小于任务声明的复算容差（建议先 0.2 K，写入报告）

通过：两次 `input_hash` 相同，容差内。失败：手工改 case 却声称同一输入。

### P1-03h 一键脚本

```bash
test/.venv/bin/python test/p1/run_room.py --input test/p1/fixtures/room_p1.json
```

通过：退出码 0 ⇔ `quality.pass==true`；stdout 含 run 目录。失败：质量失败仍退出 0。
