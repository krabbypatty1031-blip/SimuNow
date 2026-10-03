# P3-07 占用时段写入 EnergyPlus 日程

**Files:**

- Modify: `Backend/src/simunow_worker/models/l1_room.py`（映射 occupancy/hvac `OccupiedHours`）
- Modify: `test/p1/write_idf.py`（有日程则 `Schedule:Compact`；无日程保持 AlwaysOn）
- Test: `Backend/tests/test_l1_room.py`、`Backend/tests/test_l1_schedule.py`
- 依赖：P3-06

**Interfaces:**

- Consumes: `ProjectDraft.occupancy.schedule` / `hvac.schedule`（`HH:MM`）
- Produces: IDF 中 `OccupiedHours` / `HVACHours`；People/Lights/Equipment 用占用窗；IdealLoads 用 HVAC 窗
- 不产生：8760、全年电量、编造 UA、App 按钮

**约束：**

- 有日程时禁止再写成 AlwaysOn 假装全天有人
- 渗透风仍 AlwaysOn（不是人员日程）
- 无日程的 P1 房间仍 AlwaysOn，不破坏 P1 CLI
- 设定温度不是送风温度

---

### P3-07a 映射日程

- [x] office 映射含 `08:00`–`18:00`，人数 8
- [x] 不写 `ua_opaque`

### P3-07b IDF Compact

- [x] 有日程：`Until: 08:00, 0` / `Until: 18:00, 1` / `Until: 24:00, 0`
- [x] 改结束到 `12:00` 后 IDF 跟着变
- [x] 无日程：仍 `AlwaysOn`（P1 夹具）

### P3-07c 人数进入 People

- [x] `n_people` 来自 `occupantCount`，不是座位数
