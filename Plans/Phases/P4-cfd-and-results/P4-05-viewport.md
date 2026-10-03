# P4-05 视口、场格式、切片

**Files:** `Packages/SimuKit/Sources/SimuVisualization/{RoomScene,IsometricProjection,RoomWireframeView,SimulationViewport,SlicePalette}.swift`；`Packages/SimuKit/Sources/SimuCore/FieldSlice.swift`；`test/p1/field_slice.py`（`run_room.py` 调用）；`Protocols/Schemas/field-slice.schema.json`；`Fixtures/task/field-slice-l2.json`
**依赖:** P4-01 几何；场叠加依赖 P4-03 采样
**不做:** 无 L2 结果时画示意彩虹场；体积渲染冒充；粒子动画当降温时间。流线是稳态折线，不是开机降温。

**约束:** 显示 Y-up ↔ 计算 Z-up 走现有 `CoordinateMapping`。无效掩码中性色。两方案色标后由 P4-06 共用。

### P4-05a 房间几何

- [x] 盒子、窗、送回风、座位可见（`RoomScene(draft:)` 按真实草稿几何；`RoomWireframeView` Canvas 线框 + 水平拖拽 yaw；无 geometry → nil → 空状态不画假房间）
- [x] 模型不完整仍显示空状态，不画假房间

### P4-05b 场文件

- [x] float 格式、endian、轴序、单位、掩码、哈希写清（JSON 文本无 endian 问题；`field-slice.json`：unit C、coordinateSystem rightHandedZUp、axisOrder ["y","x"]、sampleMethod nearest_cell、valid 掩码、inputHash = P1 房间输入哈希；schema additionalProperties false + wire claim const 钉死）
- [x] 墙/家具内部不参与统计（`point_in_fluid` 逐格心判掩码；stats{validCount,minC,maxC} 只算有效格；invalid 显示中性灰不当 0 °C）

### P4-05c 切片

- [x] 有质量通过的场才叠坐姿高度温度切片（`write_slice(quality_pass=False)` → 不写文件；`RoomWireframeView` 无 field 不填色）
- [x] 色标带 °C；无场不填色（`SlicePalette` legend "23.9 – 25.9 °C" 物理范围；hue 2/3·(1−t) 蓝到红，clamp 不外推；`SimulationViewport(draft:field:)`）

### P4-05e 速度箭头与流线

- [x] 质量通过才写 `field-flow.json`（最近单元 U，与座位 `uMag` 同源；glyph 间距与流线密度是显示旋钮）
- [x] 3D / Canvas 叠稳态箭头与折线；箭头长度是显示放大，不是真实位移；失败场不画示意气流
