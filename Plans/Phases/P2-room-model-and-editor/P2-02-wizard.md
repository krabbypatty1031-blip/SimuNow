# P2-02 向导、尺寸、门窗、朝向、来源

**Files:**

- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift`
- Create: `Packages/SimuKit/Sources/SimuWorkspace/RoomEditorForm.swift`（Mac inspector 与 iOS 详情共用）
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift`
- Modify: `Packages/SimuKit/Sources/SimuCore/ProjectModels.swift`（仅当朝向缺字段）
- Test: `Packages/SimuKit/Tests/` 下 Workspace 或 Core 测试（store 变更，不测像素）
- 依赖：P2-01 完成

**Interfaces:**

- Consumes: `ProjectDraft` v2；`PhysicalQuantity`
- Produces: 内存中可编辑的几何；字段级 `FieldIssue`（id + 路径 + 用户可读原因）
- 不产生：磁盘保存、计算提交、3D 手柄

---

### P2-02a 房间尺寸

- [x] inspector / 详情出现 `sizeX` `sizeY` `sizeZ`，标签含单位 `m`
- [x] 修改后 `store.project.geometry` 立即更新；非正数不能写入完整模型
- [x] 默认新项目仍是 v1（无几何），用户确认尺寸后才升到带 geometry 的草稿

通过：单测改 6→7，store 中 `sizeX.value == 7`。失败：只改 Text 不改模型；或一打开就填 6×6×2.8 却标成用户测量。

### P2-02b 门窗数值编辑

- [x] 可增删 `Opening`；编辑 `wall` `s0` `s1` `z0` `z1` `kind`
- [x] `s1 > span(wall)` 或 `z1 > sizeZ` 时 `FieldIssue.path` 指向该开口，不能静默夹紧
- [x] 窗宽不是整墙宽；来源选择器使用 `ParameterSource`

通过：把窗 `s1` 设到墙外，表单显示错误且 `hasCompletePhysicalModel` 可为 false。失败：画成整墙条，或不报错。

### P2-02c 朝向

- [x] `RoomGeometry` 增加北向角（度，计算坐标，Z-up 平面）；schema / Python / Swift 同步
- [x] UI 能编辑；说明「0° 表示 +Y 为北」或文档锁定的等价约定，两端一致
- [x] 朝向变化不偷偷旋转已有 `s0`（本阶段只存角，P2-03 再处理墙面相对位置）

通过：round-trip JSON 含朝向。失败：只有 UI 文案没有字段。

### P2-02d 假设与来源

- [x] 列出 `source == assumed|preset` 的量，以及 `geometry.assumptions`
- [x] 有 `reference` 则显示；没有则显示「未知 / 无出处」，不编造文献
- [x] `uncertainty` 有则显示同单位，无则省略

通过：夹具办公室能看到 `omitted: furniture_boxes` 与若干 assumed。失败：把 unknown 显示成 0。

### P2-02e 双端复用

- [x] Mac inspector 与 iOS 详情共用 `RoomEditorForm`，不用复制两套字段
- [x] iPhone 用 sheet 或 NavigationLink，不硬塞三栏
- [x] 字段有 VoiceOver 标签（名称 + 单位，不只靠颜色）

通过：`Scripts/check.sh mac` 与 `Scripts/check.sh ios` 编译；表单类型两端引用。失败：只有 Mac 能改尺寸。

### P2-02f 不可用计算

- [x] 工作区不出现可点的「开始计算 / 提交」
- [x] 几何不完整时用空状态或文字「模型不完整」，不用假进度

通过：代码搜索无空 `Button` action 指向计算。失败：绑了空 closure。
