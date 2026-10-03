# P3-11 沙盒 App 真正跑通代表日 L1

**Files:**

- Modify: `Backend/src/simunow_worker/__main__.py`（3.9 可解析）
- Modify: `Packages/SimuKit/Sources/SimuSimulation/LocalProcessClient.swift`（不用 zsh 找 Python）
- Create: `Packages/SimuKit/Sources/SimuSimulation/WorkerTreeStaging.swift`
- Modify: `LocalProcessL1Client` / `WorkspaceStore` / `EngineBookmarkStore` / `RoomEditorForm`
- Modify: `Scripts/generate_project.py`（Mac 复制 WorkerTree 进 Resources）
- Modify: `Apps/SimuNowMac/SimuNowMac.entitlements`（hardened runtime 允许启动用户选择的 EnergyPlus）
- Test: `WorkerStagingTests.swift`、现有 `WorkspaceL1Tests`
- 依赖：P3-09、P3-10

**不做:** 关闭 sandbox、硬编码 Desktop、把 EnergyPlus 打进 git、OpenFOAM

**约束:**

- App 只要求用户选择引擎目录；worker 来自包内资源再拷进容器
- 计算只碰容器内副本或已授权的用户目录
- `/usr/bin/python3` 3.9 必须能启动 worker
- 路径不写入 `project.json`

---

### P3-11a 系统 Python 可启动 worker

- [x] `__main__.py` 带 `from __future__ import annotations`
- [x] `/usr/bin/python3 -m simunow_worker doctor` 不因 `Path | None` 崩溃

### P3-11b 容器内 worker 树

- [x] 从仓库或 Bundle `WorkerTree` 拷到 Application Support
- [x] 探测看拷贝后的 `Backend/src/simunow_worker/__main__.py`

### P3-11c App 只选引擎

- [x] 未选工作副本也能配置（有 Bundle 或已 stage）
- [x] sandbox 仍为 true
