# P3-08 Workspace 提交代表日 L1

**Files:**

- Create: `Packages/SimuKit/Sources/SimuSimulation/L1TaskClient.swift`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`
- Modify: `Packages/SimuKit/Sources/SimuCore/ProjectEditing.swift`（人数与占用时段）
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/RoomEditorForm.swift`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`（任务页）
- Test: `Packages/SimuKit/Tests/SimuCoreTests/WorkspaceL1Tests.swift`、`RoomEditingTests.swift`
- 依赖：P3-06、P3-07

**Interfaces:**

- Consumes: 完整 `ProjectDraft`、`L1TaskClient`
- Produces: `SimulationRequest` + 快照字节；Runs 页进度事件；`SimulationResult`
- 不产生：空的「开始计算」；iOS Process；OpenFOAM

**约束：**

- 按钮文案是「提交代表日 L1」，未配置时不可点
- `UnconfiguredL1TaskClient.isConfigured == false`
- `inputHash` 对快照字节；旧 run 不覆盖当前 `project`
- 缺失指标 omitted，不填 0

---

### P3-08a 人数与时段可写

- [x] `applyOccupantCount` 正数写入；0 拒绝
- [x] `applyOccupiedHours` 要求 `HH:MM` 且结束晚于开始
- [x] 同步 occupancy 与 hvac 日程（同一代表日窗，不是 8760）

### P3-08b 注入客户端可提交

- [x] 未配置：`canSubmitL1 == false`，不调用引擎
- [x] 配置后：写出 request/snapshot，receipt 进入 store
- [x] 任务页显示 JSONL 事件，不是残差百分比

### P3-08c 文案

- [x] Apps/Packages 仍无「开始计算」字符串
