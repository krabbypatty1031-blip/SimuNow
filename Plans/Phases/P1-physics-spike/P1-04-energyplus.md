# P1-04 单区 EnergyPlus

**Files:**

- Create: `test/p1/write_idf.py`（从 `test/p0/export_energyplus.py` 与 `test/cases/ep_ideal_loads_smoke.idf` 升级，Version 25.2）
- Create: `test/p1/run_l1.py`
- Evidence: `test/outputs/p1_l1/<utc>/`（idf、eplusout.end、eplusout.csv 或 eso 摘要、`l1_report.json`）

**Interfaces:**

- Consumes: 与 P1-03 同一 `room_p1.json` 的几何、人数、灯光、设备、设定温度
- Produces: `l1_report.json`：`q_cool_w`、`p_elec_w`、`cop`、`zone_mean_air_c`、面 BC 表；以及给 L2 的 `boundary.json`

Ideal Loads 是等效模型：冷量不是电耗。电耗 = 冷量 / COP（夹具 COP=3），报告必须写 `model: equivalent_ideal_loads`。

---

### P1-04a 合法 25.2 IDF

- [x] `Version, 25.2`
- [x] 含 `ZoneHVAC:EquipmentList`、`ZoneHVAC:EquipmentConnections`、`ZoneHVAC:IdealLoadsAirSystem`
- [x] `RunPeriod` 带 Begin/End Year 空位（9.6+ 字段）
- [x] 恒温器控制类型为 DualSetpoint（控制类型日程为 4，不是占用率）
- [x] Space Name 留空；楼板/屋顶顶点朝向使 EnergyPlus 不报 upside-down 为 Fatal

通过：`energyplus -x -w <epw> -d <out> room.idf` 生成 IDF 无 Severe 导致终止。失败：缺 EquipmentList。

### P1-04b 代表日运行

- [x] 使用 P1-01b 的 EPW
- [x] `eplusout.end` 含 `EnergyPlus Completed Successfully`
- [x] 输出变量至少：区平均空气温度、Ideal Loads 总冷量
- [x] 单位核对：能量 J→W 或 kWh 的换算写在 `l1_report.json`（注明时段长度）
- [x] 禁止输出「年节能量」

```bash
test/.venv/bin/python test/p1/run_l1.py --input test/p1/fixtures/room_p1.json
```

通过：`l1_report.json` 有 `q_cool_w > 0` 且 `end` 成功句。失败：Fatal 或用 DesignDay 冒充天气却声称香港代表日。

### P1-04c 电耗标注

- [x] `p_elec_w = q_cool_w / cop`
- [x] 字段 `equivalent: true`；容量 NoLimit 时写「未做设备容量校核」
- [x] 不得把 Ideal Loads 供冷当成室外机电表

通过：报告同时有冷量与电耗且比值 = COP。失败：只有冷量却写「用电」。

### P1-04d L2 边界

- [x] `boundary.json`：每个表面 `bc_kind` 为 `temperature` **或** `heat_flux` 之一，不同时强制
- [x] 送风 T、质量流来自设备/夹具假设，来源字段必填
- [x] 室内机位置改变不自动写死节电系数

通过：L2 管线能读该文件（P1-03 第二轮可引用）。失败：墙温与热流双加。

### P1-04e 与 L2 热源口径

对照表写入 `l1_report.json`：

| 项 | L1 (W) | L2 (W) |
|---|---|---|
| 人员显热 | | |
| 灯光 | | |
| 设备 | | |
| 窗 | | |

- [x] 人数 × 每人 W 与夹具一致
- [x] 差大于 5% 必须解释（辐射/对流拆分），不得静默

通过：表完整。失败：L2 人体热源与 L1 人数对不上仍标一致。
