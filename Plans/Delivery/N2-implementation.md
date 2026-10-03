# N2 实现与交接记录

日期：2026-10-03。独立 worktree `native-n2`，基点 `3ea5b56`。本文件记录 N2 的规划、真实接口、验证与自审；总状态和人工验收由根代理整合。

## 执行规划

1. N2-01：建立 Foundation-only、Sendable 的场景描述、稳定业务键、墙面 UV 映射与开口分格。以现有 registry 解码矩形房间和轴对齐盒体，严格检查有限正尺寸；未知/无效对象列出原因，绝不猜测几何。保留 domain 米制 Z-up，唯一转换器负责 Apple 坐标。
2. N2-02：在 macOS 15 / iOS 18 availability 内建立非 AR RealityView。MainActor 创建世界/房间/对象/overlay 根和单一相机。共享单位 mesh 缩放形成家具与外向 0.02 m 显示墙厚；开口对应墙片真正缺省。设备、座位与点位使用有说明的符号。
3. N2-03：纯相机状态提供宽高比适配、等轴/俯视、聚焦、有限旋转缩放；实际相机由同一控制器更新，native camera controls 为 none。三维模型 ID 选择映射回现有 P2 表单；门窗/墙面通过房间/开口编辑器，不另造输入事务。对象列表与相机按钮提供可访问替代。
4. N2-04：按稳定节点键分类 diff，保持相机、只更新改变对象。每视口独立控制器，无共享 Entity；离开/后台清理输入订阅与可重建资源。旧系统保留完整二维和对象列表。提供纯 overlay 路径接口供 N3 接入，N2 不生成任何规则结果。
5. N2-05：对照 V-N2-01…11，单测坐标/家具中心/六面开口/实际缺格/稳定 diff/相机与选择。两端正常构建和独立 N2 验证产品；运行时、手势、最低系统、可访问性与性能严格单列，不能由编译代替。

## 文件归属与边界

本代理只改 Visualization/RoomScene、Visualization/RealityKit 的生产 renderer，Workspace/RoomScene、RoomObjectsView 与必要的 WorkspaceView 连接，相关测试，以及 App 的编译旗标验证入口。本文件之外的 Plans、用户 scheme、Pitch 与主工作区不修改。项目 v2 / N1 Codable、分析 hash 与 Core 协议不修改；相机、选择、隐藏墙和显示厚度不写项目或输入 undo。

## 实现、接口与证据

待实现后填写；尚未以任何构建替代实际平台验收。

## 实际接口与接入

| 位置 | 已实现接口与责任 |
|---|---|
| Visualization/RoomScene/SceneObjectKey.swift | category + 原模型 UUID、稳定 SceneNodeKey；RoomSceneSelectionTarget 把业务选择映射到 P2 object/room/opening 表单 |
| SceneDescriptor.swift | Sendable/Equatable 纯节点、对象说明、显示问题和稳定 revision；米制 Z-up，不读文件、不含 Entity；RoomOverlayPath/RoomSceneOverlay 是显示路径接口 |
| OpeningGeometry.swift | 六面 UV/法线/外向 winding、严格开口尺寸检查、确定性矩形分格与真实开口减格；0.02 m 墙厚仅向域外 |
| RoomSceneBuilder.swift | registry 解码已知 room/box/split；盒体中心 origin+size/2；逐模型排除未知、越界、无效与重复 ID；符号保留 UUID 与示意说明；northAngle 只参考箭头 |
| SceneDiff.swift | added/removed/geometry/transform/material/selection 分组，节点键稳定；单位置修改不重造别的实体 |
| RoomCameraState/RoomSceneHitTester.swift | 纯相机 FOV/球界适配/有限 orbit、zoom、top、reset、focus；依据真实视口生成射线，取当前可见几何的最近正 t |
| RoomSceneBuildInput/SelectionAdapter.swift | 完整构建源冻结与实时匹配；旧画面可保留但不选择新输入；每次编辑重新核对当前项目、方案与嵌套/父 ID |
| RealityKit/RoomEntityFactory/MaterialPalette | MainActor 实体/mesh/材质；共享单位 box/sphere/cylinder/cone mesh；独立 world/room/objects/overlay/camera；无 AR、相机权限或纹理下载 |
| RoomSceneController/RoomCameraController | 单自管 PerspectiveCameraComponent，explicit vertical FOV；按 diff 更新、保存显示相机、选择高亮、墙显隐；每视口独立，暂停/清理可重建资源 |
| RealityKitRoomViewport/RoomScrollCapture | macOS 15 / iOS 18 完整隔离；SwiftUI drag/tap/pinch 与 Mac 窗口/视口限定滚轮监听；dismantle 移除唯一 local monitor；没有 SceneEvents 订阅或动画 ticker |
| Workspace/RoomScene/RoomViewportContainer | 后台纯值构建并传播取消；保持 RealityView 实例和视角，更新中锁旧选择；完整原 RoomPlanView 回退、门窗/表面清单、未知问题定位与文字说明 |
| RoomObjectsView/WorkspaceView | 当前 ID 选择→原草稿表单→replaceProject 完整事务与 undo；删除/方案切换清理失效选择，移除按 scenario/focus 强制重建视图的 .id |
| Apps + NativeRoomSceneProbeHostView | 正常 DocumentGroup 保留；Mac Debug Developer 菜单与 SIMUNOW_ROOM_PROBE 独立直接 WindowGroup；固定 UUID 的 synthetic F-A/F-B，局部深色/最大字号/强制二维验证；Release 不含 N2 测试界面 |

相机策略由 N1 实际自管相机能力和公开 SDK 核对支持。三维点选使用显示几何射线，避免非 AR Mac 的 targeted gesture 差异；碰撞与 InputTarget 只用于显示输入，不参与气流判断。显式 vertical FOV 与纯射线的水平/垂直视角一致，见 [Apple PerspectiveCameraComponent](https://developer.apple.com/documentation/realitykit/perspectivecameracomponent/fieldofviewindegrees)。门窗使用轮廓线与墙片缺省，不用透明贴片伪造开口。

### N3 / N5 调用约定

- Workspace 把已经通过 run identity/hash/freshness/checks 的结果转换为 `RoomSceneOverlay(paths:explanation:)`，传入 `RoomObjectsView(overlay:)` 或 `RoomViewportContainer`。N2 从不决定结果是否新鲜，也不重新算规则。
- 路径点是 domain 米制 Z-up；每条 2…129 个点、最多 64 条、ID 唯一且有限坐标。非法输入明确列显示问题、拒绝绘制整份 overlay，不 silently 降密度。
- N2 的最小 overlay 实现每段一对 Entity/ModelEntity；64×128 约有 16k 附加实体。因此 N3-04 必须改为合并 mesh/有限路径实体再做满预算性能验收，不能把 overlayPathCount=64 当实际实体数。`statistics.entityCount` 为递归真实实体数；meshCount/materialCount 是可重建缓存数。
- RoomObjectsView 的 rendererCapability 可注入二维分支；正常 `.current` 仍由系统 availability 决定。强制二维验证只证明分支，不能当 macOS 14 / iOS 17 运行证据。
- 相机/选择/显隐/墙厚都不 Codable，不进入 project、analysis config/hash 或输入 undo。生产默认没有任何气流、温度、舒适或费用结果。

## 自动验证与自审

`Scripts/check.sh test`：124 项 Swift 共享测试通过（N1 105 + N2 19），Extension 2 项另列；最终日志 `Artifacts/N2/swift-test.log`。正常 mac/ios 与两端 probe 构建日志在同目录。最低 deployment target 仍 macOS 14 / iOS 17，未更改 scheme、pbxproj、依赖、sandbox 或共享 JSON 协议；本阶段没有需要同步的 Swift/Python Codable 变更。

自审修复：未知类型不生成默认几何；全 category 的重复模型 UUID、重复方案身份不能生成不可区分对象；非有限/越界点和不可显示尺度严格排除；显示问题附着到对象文字；墙厚只向外；维度重排不带负号；box pivot 取中心；six-face winding 保持右手性；vertical FOV 与纯 picking 一致；相机/overlay 刷新不强制重造视图；完整冻结构建输入保护旧图点击；后台构建循环响应取消；MainActor.assumeIsolated 只返回 Sendable Bool，不跨域返回 NSEvent；窗口限定 local wheel monitor 在 dismantle 释放；真实实体统计和路径条数区分。

| 验收案例 | 已有证据 / 仍需实际范围 |
|---|---|
| V-N2-01 | roomSceneCoordinatesKeepHandednessAndPositiveDimensions：三基向量、往返、6×4×3 正尺寸，northAngle 不二次旋转 |
| V-N2-02 | roomSceneBoxesUseCentersAndNeverRepeatNorthRotation / SymbolsPreserveModelIDsAndExplainTheirSizes：origin(1,2,.5)→center(2,2.5,1)，原 UUID 与无机身尺寸说明 |
| V-N2-03 | roomSceneOpeningMapsAllSixFacesAndPreservesOutwardWinding / UnknownAndInvalidGeometry：六面不同 UV、domain/Apple 法线与 winding、未知开口不猜值 |
| V-N2-04 | OpeningsSubtractRealWallCellsAndKeepThicknessOutside / DuplicateIdentities：缺格面积、开口射线贯通、外向 .02 m、未知/重复明确排除；根代理已实际观察 Mac 门窗空洞及薄盒 |
| V-N2-05 | CameraFitsPortraitAndLandscapeWithoutMirroring / CameraPresetsFocusAndRepeatedZoomStayFinite / DisplayChangesDoNotTouchInputHashesOrUndo：宽窄适配、10%边距、top/reset/focus/有限缩放；根代理报告 Mac drag/scroll/top/focus 实际响应 |
| V-N2-06 | SelectionAdapterRevalidatesParentsDeletesAndScenarioScope / OldBuildCannotSelectNewInputsWithSharedNestedIDs：嵌套/父 ID、删除/重复方案/旧构建锁定；根代理报告 Mac 3D点选→P2 X=4→4.5 应用/重开→undo→4.0 重开通过 |
| V-N2-07 | 正常及 probe 两端编译通过；根代理已实际 Mac F-A/F-B；iPhone/iPad 手势和操作范围由根代理补证，不能用编译代替 |
| V-N2-08 | 最低 target 编译与 availability 隔离通过；现代 Mac 强制二维已实际显示相同尺寸/门窗/薄盒/风口；真正 macOS 14 / iOS 17 运行时不可用，保留未验证 |
| V-N2-09 | 对象/门窗清单、相机按钮、文字状态与 adaptive 控件已实现；Debug 深色/最大字号开关只作用于验证副本。实际 VoiceOver/大字号/移动端范围由根补证 |
| V-N2-10 | ControllerRetainsEntitiesAndCameraForSingleObjectDiff / ControllerTwentyLifecyclesAndWindowsAreIndependent / CancelledBackgroundBuildStopsBeforeCreatingNodes：20 次 controller 清理、无 ticker/scene订阅、独立相机/Entity、单节点复用、任务取消；真正开关窗口20次与系统前后台仍需根补证 |
| V-N2-11 | CameraLeavesNativePackageAndOpaqueAttachmentsUnchanged：真实临时磁盘 .simunow 关闭重开、project.json/metadata.json 字节及 opaque 大整数/binary 附件不变。旧 P2 全套回归通过；真实 FPS、峰值内存和各平台文档操作仍需根记录 |

## 剩余验收边界

本类别生产 renderer、相机、选择、diff、完整二维回退和 N3 overlay 接入代码已完成。剩余为实际平台/设备验收：最低 14/17、移动端手势与无手势编辑、VoiceOver、最大字号与横竖屏、真实窗口生命周期和显示性能。没有物理计算或 N3 规则实现；静态方向箭头仅展示输入方向。总台账由根代理按真实截图/操作记录更新，本文件不把这些未验证项标为通过。
