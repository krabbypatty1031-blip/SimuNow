# P3-10 结果展示与失败不坏项目

**Files:**

- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`
- Test: `Packages/SimuKit/Tests/SimuCoreTests/WorkspaceL1Tests.swift`
- 依赖：P3-08

**Interfaces:**

- Consumes: `SimulationResult`、`L2BoundaryMapping`
- Produces: 电耗/冷量/边界只读展示；freshness；取消/失败保留当前草稿
- 不产生：逐点 CFD、全年电量、把 omitted 显示成 0

**约束：**

- 送风温度不是设定温度
- 回风 ≠ 新风；循环风 = 送风 − 新风
- 改人数或时段后旧结果标 stale，不覆盖 `project`
- 取消幂等；失败不写假瓦特进当前方案

---

### P3-10a 展示

- [x] `q_cool_w` / `p_elec_w` 有单位；`annual_kwh` 显示未知
- [x] 边界：供给 16、设定 26、回风口独立

### P3-10b 新鲜度

- [x] 当前快照哈希 ≠ 结果 `inputHash` → stale
- [x] 再提交成功才变 fresh

### P3-10c 安全

- [x] 失败 / 取消后 `project.occupantCount` 与几何不变
- [x] 打开包仍忽略未完成 run（P3-05c）
