# P2-04 项目包保存与导入

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/ProjectPackage.swift`（纯 Foundation，无 AppKit）
- Create: Mac 适配：安全书签 / NSSavePanel 放 `Apps/SimuNowMac` 或 Workspace 的 `#if os(macOS)` 适配器，不得泄漏到 iOS 编译
- Create: `Packages/SimuKit/Tests/` 包 round-trip 测试（临时目录）
- 依赖：P2-01；建议 P2-02 已能编辑，否则只能存夹具

**Interfaces:**

- Consumes: `ProjectDraft` JSON
- Produces: `*.simunow` 目录包（或 zip 等价，需在 ADR 锁定一种）
- 不产生：runs、场文件、绝对私有路径

目标布局（本阶段最小集）：

```text
Project.simunow/
  project.json     当前 ProjectDraft
```

`geometry/`、`runs/` 可空着不写。P3 再加 input 快照。

---

### P2-04a 原子写入

- [x] 先写临时目录，成功后再替换目标包
- [x] 中途失败保留旧包或不留半截 `project.json`
- [x] 测试在 `FileManager.temporaryDirectory` 下进行，禁止写开发者 Desktop

通过：写入中抛错后旧 JSON 仍可读。失败：直接覆盖到一半。

### P2-04b 关闭重开

- [x] 保存再加载后 `ProjectDraft` 相等（或文档化的合法规范化，如省略空 reference）
- [x] v1 包加载为不完整模型，不填默认房间
- [x] 两端能打开同一包字节（Mac 存、模拟器读同一 fixture）

通过：夹具 v2 办公室 round-trip。失败：UUID 每次保存都变。

### P2-04c 损坏与版本

- [x] 缺 `project.json` / JSON 非法 / `schemaVersion` 未知 → 结构化错误，含修复建议
- [x] 不崩溃；UI 显示错误文字
- [x] 未来字段：未知可选键按 Codable 策略忽略，并记录「未识别字段不参与求解」

通过：坏文件测试。失败：`try!` 解包崩溃。

### P2-04d 路径

- [x] `project.json` 不含 `/Users/`、`/Downloads/` 等本机绝对路径
- [x] 天气或资源若出现，只用包内相对路径（本阶段可暂无资源文件）

通过：对保存结果扫描绝对路径失败。失败：把 NSSavePanel 路径写进模型。

### P2-04e 按钮可用性

- [x] 实现保存之后才显示「保存」的可用按钮
- [x] 实现导入之后才显示「打开 / 导入」
- [x] 未实现前保持空状态，不绑空 action

通过：对照 Workspace UI 与适配器。失败：菜单项可点但 no-op。
