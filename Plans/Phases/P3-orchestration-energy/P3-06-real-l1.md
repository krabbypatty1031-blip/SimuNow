# P3-06 接入真实 L1（EnergyPlus 代表日）

**Files:** worker `run-l1`、P2→P1 房间映射、Mac executor 默认走 `run-l1`  
**依赖:** P3-02 执行器、P3-03 会计、P1-04 CLI  
**不做:** App「开始计算」按钮、全年电量、编造 UA/SHGC、把 Ideal Loads 当实测电表

**约束:** 缺引擎 / 缺天气 → failed 或 omitted，瓦特不得填 0；设定温度 ≠ 送风温度；`p_elec = q_cool / COP`。

### P3-06a 草稿 → L1 房间

- [x] office 映射含 size / supply 16 / 人数显热；不写伪造 `ua_opaque`
- [x] 窗面积用墙面补丁，不是墙宽

### P3-06b 无引擎不得编造

- [x] `run-l1` 在 `SIMUNOW_ENGINES_ROOT` 缺失时 failed + 无 q_cool
- [x] stub-task 测试仍显式走 stub

### P3-06c 有引擎跑代表日

- [x] 本机 `test/engines` 跑通时写出 `q_cool_w` 与 `p_elec_w`，`annual_kwh` omitted
