# N2：RealityKit三维房间查看

版本：详细执行稿v1，2026-10-03。状态：N2-01…05代码已整合（e2ea5f5），124项共享Swift测试与主工作区Mac/iOS构建通过；Mac三维/P2编辑闭环和现代移动端渲染已观察。完整平台/可访问性/性能仍待验，详见[交接](../Delivery/N2-implementation.md)与[逐项台账](../Delivery/native-acceptance-status.md)。前置N1-01…03、P2；算法结果不是创建几何场景的前置。下方清单保留要求，不把部分验收自动勾选为全通过。

## 目标、输入与输出

输入当前项目几何、所选方案对象、现有选择和renderer capability。输出可旋转/缩放/重置/选取的非AR房间；选择对象继续进入P2表单，不另建几何编辑器。三维只是显示模型，Analysis算法只接纯值。

开工读[执行规范](../References/10-ai-execution-guide.md)、[验收案例](../References/11-native-acceptance-cases.md)，确认[CoordinateTransform](../../Packages/SimuKit/Sources/SimuVisualization/CoordinateTransform.swift)、[PlanProjection/选择类型](../../Packages/SimuKit/Sources/SimuVisualization/RoomPlan/PlanProjection.swift)、[RoomObjectsView](../../Packages/SimuKit/Sources/SimuWorkspace/ObjectEditor/RoomObjectsView.swift)和WorkspaceView已有连接。

## 任务索引

| ID | 依赖 | 产物 |
|---|---|---|
| N2-01 | N1-01/03 | 可单测纯SceneDescriptor、门窗面映射 |
| N2-02 | N1-02、N2-01 | RealityView renderer和基础实体 |
| N2-03 | N2-02 | 相机控制、模型ID选择与P2属性连接 |
| N2-04 | N2-01…03 | diff/lifecycle/capability/二维回退 |
| N2-05 | N2-01…04 | 坐标、平台、文档、可访问性验收 |

纯descriptor可与N3并行；renderer/WorkspaceView公开连接交给一个整合人。保留二维投影、数值编辑及DocumentGroup。

## N2-01：纯场景描述与坐标规范

**新增位置**：Visualization/RoomScene/{SceneDescriptor,RoomSceneBuilder,OpeningGeometry,SceneObjectKey}.swift。测试放RoomSceneTests.swift；descriptor不importRealityKit。

执行步骤：

- [ ] 定义SceneObjectKey(category,modelID)，用现有UUID构成稳定节点；face分段子mesh只用稳定subIndex，不生成新业务UUID。
- [ ] SceneDescriptor包含米制Z-up bounds、节点kind/transform/geometry、selectionKey、来源问题和revision；所有数据Sendable/Equatable。
- [ ] 通过registry解析RectangularRoom/BoxObstacle；未知类型保留为明确未显示对象，不用固定1米立方体代替。
- [ ] 房间六面、门窗、家具生成geometry；座位/采样/设备热源/风口/温控点用显示符号；空调机身无尺寸，符号标记“示意”。
- [ ] 方盒mesh以中心为pivot：center=origin+size/2；不能把Core.origin直接作为generateBox中心。
- [ ] 计算门窗所在面局部坐标，按下表映射；offsetU/V不是相对墙中心；窗/门的宽高/边界缺失时列问题而非猜开口。
- [ ] 单位与变换在一个adapter转换；northAngle只显示朝向参考，不再次旋转已在domain定义的房间/对象。

面坐标约定（与现有surfaceExtent一致）：

| face | 位置映射(u,v) | domain法线 |
|---|---|---|
| xMin | (0,u,v) | (-1,0,0) |
| xMax | (width,u,v) | (+1,0,0) |
| yMin | (u,0,v) | (0,-1,0) |
| yMax | (u,depth,v) | (0,+1,0) |
| floor | (u,v,0) | (0,0,-1) |
| ceiling | (u,v,height) | (0,0,+1) |

domain→Apple的位置/方向均为(x,z,-y)；正尺寸(width,depth,height)重排为(width,height,depth)，不能产生负深度。四边门窗几何同样走该转换；winding/法线独立处理。

**验证/完成**：V-N2-01…04；对非正方房间、非零家具origin、六面开口和三个基向量有golden位置。descriptor不读文件、不含Entity，也不计算热量或费用。

## N2-02：RealityKit实体与简洁房间

**位置**：Visualization/RealityKit/{RealityKitRoomViewport,RoomEntityFactory,RoomMaterialPalette}.swift；保留SimulationViewport原空状态并按真实项目切换。

执行步骤：

- [ ] 所有Entity创建/修改MainActor；RealityView类型和构造完整availability保护；设置virtual camera，不开启spatialTracking。
- [ ] 建worldRoot、roomRoot、objectsRoot、overlayRoot和单一camera；根层次避免一个对象有多套坐标转换。
- [ ] 墙显示厚度首用0.02m内部显示假设，内表面位于domain边界、厚度向外，不能改变流体域或物理墙参数。
- [ ] 在墙局部UV收集边界/开口边界，把矩形分格，开口内部格不生成墙片；保留opening轮廓和实体ID，避免把透明贴片当真实开口。
- [ ] 默认隐藏天花板；用户可隐藏前侧墙辅助查看。只改变render visibility，分析边界和家具碰撞仍完整。
- [ ] 家具使用共享box mesh+scale，简单语义材质；设备/关注点符号与实际尺寸分开；缺失对象有列表可定位。
- [ ] 用CollisionComponent/InputTarget等公开能力支持选择，碰撞体只用于hit-test，不作为风路算法。
- [ ] 材质兼容深浅色、明确透明设置和双面/法线策略；先固定照明，不增加重阴影/纹理下载。

**验证/完成**：V-N2-04/07。两端能看见同尺寸房间和开口；无摄像权限；未知项目没有假物体；所有符号来源可解释。mesh构建较大时后台仅生成纯数组，Entity仍MainActor。

## N2-03：相机、选择与属性连接

**位置**：Visualization/RoomScene/RoomCameraState.swift（纯值）、RealityKit/RoomCameraController.swift、Workspace/RoomScene/RoomViewportContainer.swift。

默认设计采用单一自管虚拟相机、公开PerspectiveCameraComponent和自定义orbit状态，原生gesture camera controls设none；N1-02必须先证实目标SDK中camera实体可控制视角。若不能证实，先记录阻断，不写两个控制器相互覆盖。公开native orbit/dolly只作为spike备选，在ADR确定一种策略后统一实现。

执行步骤：

- [ ] CameraState保存target、distance、yaw、pitch、projection/FOV；显示状态不进入analysis hash/project模型。
- [ ] 初始target为房间bounds中心；等轴视角yaw45°、pitch35°；FOV45°作为内部显示选择；距离由bounding sphere/视口宽高比计算并加10%边距，避免只适配正方视口。
- [ ] 鼠标/触控拖动旋转，滚轮/捏合改distance；距离在房间对角线0.25…5倍内限制，pitch避免look-at极点；俯视预设接近90°并明确up，不能意外翻转。
- [ ] 俯视、等轴、重置、选中聚焦均实际更新相机；重置只重置CameraState，不重建项目/清空结果。
- [ ] tap命中稳定selectionKey，向Workspace回调；复用RoomPlanSelection可表示的对象，surface/opening用统一选择adapter扩展，不能用Entity引用作为业务选择。
- [ ] 对应P2编辑sheet使用当前模型版本；提交走replaceProject事务和已有草稿过期检查；选择/相机不进undo。
- [ ] 选择被删除时清理；undo恢复对象后按现有规则处理选择；方案切换使selectionKey范围有效。
- [ ] 提供对象列表/键盘聚焦替代，VoiceOver可直接打开表单；旋转手势与选择手势不要同时提交编辑。

**验证/完成**：V-N2-05/06/09。相机操作不会改hash/undo；focus后对象可见；编辑设备方向后3D与俯视一致；后台结果刷新不会突然重置视角。

## N2-04：增量更新、两端入口和生命周期

**位置**：RealityKit/RoomSceneController.swift、SceneDiff.swift、WorkspaceView的最小连接；Apps capability注入。不要让各平台复制一套scene builder。

执行步骤：

- [ ] 用SceneObjectKey建立Entity映射；diff分added/removed/geometry/transform/material/selection。修改一个位置只更新该实体，尺寸变化复用mesh，必要才重建开口墙片。
- [ ] descriptor revision包含相关几何和所选方案，不以当前时间强制每帧刷新SwiftUI。
- [ ] 保留相机状态，方案切换只更新相关对象/overlay；项目根ID改变才重置适当显示状态。
- [ ] macOS15/iOS18切RealityView，14/17切既有RoomPlanView和对象列表；viewMode开关文字说明实际能力。
- [ ] 每个文档窗口拥有独立scene controller/camera/selection；不把Entity设为共享singleton。算法client可共享，场景不可共享。
- [ ] onDisappear/关窗取消scene订阅/Task和动画ticker；下一次appear只建立一次，不能重复订阅事件。
- [ ] scenePhase后台暂停可选动画；iOS内存紧张清可重建mesh/材质缓存，不丢项目或已固定结果。

**验证/完成**：V-N2-10/11。20次打开/关闭无持续任务增长；两个窗口改变相机互不干扰；old renderer实际可操作；没有为兼容提高最低版本。

## N2-05：坐标、文档与可访问性最终验收

执行步骤：

- [ ] SwiftPM测basis转换、origin/center、opening映射、selection key/diff、camera bounds；不写只断言构造器赋值的测试。
- [ ] Mac+iPhone+iPad检查尺寸、方向、门窗/家具、选择、键盘/触控、俯视/等轴/reset/focus，逐项保存V-N2证据。
- [ ] 深浅色、最大动态字号、VoiceOver、Reduce Motion、横竖屏；对象列表能完成所有属性编辑。
- [ ] 打开P2旧包、未知附件、修复项目；保存关闭重开，输入JSON/metadata保持一致，不把显示墙厚或相机写入物理模型。
- [ ] 量测目标设备帧耗时、entity/mesh数量和峰值内存；约30fps为初始目标，性能未测不宣称通过。
- [ ] mac/ios构建；有模型/协议变化再contracts。最低系统缺运行时明确未验证，不以generic build替代。

**交接**：N3拿到overlay纯路径接口、能力分支和selection映射；N5拿到三维/二维工作区入口、对象列表和平台证据。N2不产出气流、温度、PMV或电费结果；拖拽手柄、扫描、材质资产库延期。
