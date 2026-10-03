# P2-03 家具、设备、座位与坐标

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/RoomValidation.swift`
- Create: `Packages/SimuKit/Sources/SimuCore/CoordinateMapping.swift`
- Modify: `Packages/SimuKit/Sources/SimuWorkspace/RoomEditorForm.swift`
- Modify: `Packages/SimuKit/Sources/SimuVisualization/SimulationViewport.swift`（俯视占位，可选）
- Test: Core 校验单测为主
- 依赖：P2-02a/b（有房间尺寸与开口）

**Interfaces:**

- Consumes: `RoomGeometry.contains`、`HVACModel.supplyAirflowMatchesSpeed`
- Produces: `ValidationReport`（阻断项列表，含字段路径）
- 不产生：RealityKit 手柄、扫描导入、求解

Apple 显示坐标到计算坐标（米、右手 Z-up）只允许出现在 `CoordinateMapping`。View 不得各自乘旋转矩阵。

---

### P2-03a 盒体家具

- [x] 可增删 `ObstacleBox`（origin + size，米）
- [x] 盒体超出房间或与墙相交 → 阻断；`FieldIssue` 指向该 id
- [x] 空数组合法，且 `assumptions` 保留 `omitted: furniture_boxes` 或在加入后删除该假设

通过：origin.x + size.x > sizeX 的测试失败校验。失败：穿墙仍 `hasCompletePhysicalModel == true` 且无错误。

### P2-03b 送回风口

- [x] 编辑 supply / return 的 `wall` `s0` `s1` `z0` `z1`
- [x] 两口 ID 稳定，不因数组重排改变
- [x] 口必须在所属墙矩形内；送回风不能合成一个 patch
- [x] 室外新风 `outdoorAirM3s` 与回风口分开编辑

通过：把送风口移到墙外则校验失败。失败：只改 inspector 文案不改模型。

### P2-03c 座位

- [x] 增删座位；`id` 为稳定字符串（如 `S1`），不以数组下标当身份
- [x] 采样点在流体域：不在墙内、不在家具盒内、`0 < z < sizeZ`
- [x] 人数 `occupantCount` 与座位数允许不等；热源用 occupancy 功率，不用座位个数冒充人数

通过：座位放到 x=-0.1 被拒绝。失败：用 (0,0,0) 当有效采样。

### P2-03d 坐标转换

- [x] `CoordinateMapping`：计算系 Position3D ↔ 显示系（文档锁定轴）
- [x] 单测：正向再反向误差低于 1e-9 m
- [x] Workspace / Visualization 只调用该类型，不写第二套公式

通过：映射测试。失败：SwiftUI 里出现临时 `yUp` 乘法。

### P2-03e 风量互校

- [x] UI 显示送风面积、速度、`supplyAirflowM3s`
- [x] 改面积或速度可重算流量；三者不一致（相对误差 > 5%）列为阻断
- [x] 不把不一致标成「已通过」

通过：把流量改成 9，校验失败。失败：只显示速度。

### P2-03f 放置方式

- [x] 数值编辑必须可用
- [x] 俯视点击放置为 Should：有则点落在计算坐标；没有则清单注明「仅数值」
- [x] 明确不做 3D 拖拽手柄（P6/产品阶段）

通过：数值路径可完成一套办公室。失败：没有数值入口，只承诺以后拖拽。

### P2-03g 撤销范围

- [x] 在 `Plans/Delivery/decisions.md` 写 ADR：本阶段不撤销 / 仅内存撤销 / 可持久化撤销
- [x] 选择与实现一致；未实现就不显示撤销按钮

通过：ADR 有日期与选择。失败：菜单有撤销但无栈。
