# P3-03 时间表/天气到 L1，容量与电耗分开

**Files:**

- 复用 P1 L1 管线；adapter 读 P2 快照 + 天气/时间表哈希
- 写 `SimulationResult` 指标：`q_cool_w`、`p_elec_w`
- 依赖：P3-02

**Interfaces:**

- Consumes: 完整 `ProjectDraft`、天气文件哈希、代表日
- Produces: L1 result（方法名、有效 COP、单位）
- 不产生：逐点 CFD、全年节能、假置信度

**约束：**

- `q_cool_w` 与 `p_elec_w` 分字段；不得把额定冷量当电耗
- 无曲线时用有来源的等效 COP，并写 method
- 一天不能推全年

---

### P3-03a 天气与时间表

- [x] 天气文件路径相对包；哈希写入 request/result
- [x] 缺天气标 omitted，不填 0 负荷

### P3-03b 容量与电耗

- [x] 断言 `p_elec_w * cop ≈ q_cool_w` 或写明设备对象出处
- [x] 设定温度不写入送风温度

### P3-03c 代表日

- [x] result 带日期范围与 fidelity=`l1`
- [x] 单位 W，不是无量纲
