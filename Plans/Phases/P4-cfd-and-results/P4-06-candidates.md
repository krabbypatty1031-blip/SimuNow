# P4-06 基准与两候选

**Files:** `Packages/SimuKit/Sources/SimuCore/CandidateRun.swift`（口径守卫 + 冻结快照）；`Packages/SimuKit/Sources/SimuWorkspace/{WorkspaceStore,WorkspaceView}.swift`（pin / 对比页 / 共用镜头与色标）；`Packages/SimuKit/Sources/SimuVisualization/{RoomWireframeView,SimulationViewport}.swift`（外部 yaw 与 sharedPalette）；测试 `CandidateRunTests` / `WorkspaceComparisonTests`  
**依赖:** P4-02…05  
**不做:** 各自归一化色标；把 stale 场当当前；P5 建议卡、费用与 PDF

**约束:** 同一代表工况口径（天气/人数/时段）。输入哈希、网格、quality 可追溯。

### P4-06a 同口径

- [x] 基准 + 两个候选各有 run ID（`CandidateRun` 固定 `identity`（runID/scenarioID/inputHash）+ `state`/`quality`/`metrics`/`slice`/`basis`/`draft` 冻结快照；任务页「固定为对比候选」，stale 结果拒绝固定——固定的是当前口径，不是别人跑的数）
- [x] 口径不同禁止并排有效比较（`CandidateRun.basisMismatch`（人数/占用时段/设定温度/送风温度）任一不同 → 中文 reason；对比页橙色警示「口径不同（…），并排数值不是有效比较」，不静默并排）

### P4-06b 显示

- [x] 共用镜头与色标（页级 `comparisonYaw` 一个镜头转所有候选；对比页色标是所有质量通过切片的联合 min/max；工作区单场用本场 stats，不锁色标；`SimulationViewport(draft:field:sharedPalette:yaw:)` 透传）
- [x] freshness 与 quality 独立（`candidateFreshness(record)` 对当前输入哈希判 current/stale，与 record 自身 quality 并排显示，互不覆盖；质量失败候选可固定并如实显示 failed + 无切片）

**手测（2026-10-03 Debug）**：两列并排——降低送风口 24.21–24.50 °C（stale + passed）与默认口 24.43–24.73 °C（current + passed）；共用色标 23.0–25.2 °C；PMV 均不可评价。详情见 `Plans/Delivery/verification.md`。
