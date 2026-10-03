# P3-09 Mac 沙盒下引擎与 worker 路径

**Files:**

- Create: `Packages/SimuKit/Sources/SimuSimulation/LocalEngineProbe.swift`
- Create: `Packages/SimuKit/Sources/SimuSimulation/LocalProcessL1Client.swift`（`#if os(macOS)`）
- Create: `Packages/SimuKit/Sources/SimuWorkspace/EngineBookmarkStore.swift`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/ProjectLocationPicker.swift`
- Modify: `Apps/SimuNowMac/SimuNowMac.entitlements`（保留 sandbox；加 bookmark）
- Test: `Packages/SimuKit/Tests/SimuCoreTests/LocalEngineTests.swift`
- 依赖：P3-08

**Interfaces:**

- Consumes: 用户选择的工作副本根、`test/engines` 等价目录（安全书签）
- Produces: 配置后的 `LocalProcessL1Client`（`SIMUNOW_ENGINES_ROOT`）
- 不产生：关闭 sandbox；硬编码 Desktop；iOS 本地求解

**约束：**

- `com.apple.security.app-sandbox` 保持 true
- 缺 EnergyPlus 或 worker → `isConfigured == false`，按钮不可点
- 路径不写入 `project.json`
- 日志仍去掉家目录

---

### P3-09a 探测

- [x] 同时有 `Backend/src/simunow_worker/__main__.py` 与可执行 `EnergyPlus/energyplus` 才配置
- [x] 缺任一则未配置

### P3-09b 书签与权限

- [x] 目录选择经 Open 面板；书签只存 UserDefaults
- [x] entitlements 仍启用 sandbox

### P3-09c 真跑（有引擎时）

- [x] SwiftPM / 已选目录下 `submitL1` 能写出 `q_cool_w`（与 P3-06 同一口径）
