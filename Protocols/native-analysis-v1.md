# Swift 本地分析 v1

N1 实现的独立边界，使用 camelCase、UTF-8 JSON、米制/右手 Z-up。`ProjectDocument`/`ScenarioInputSnapshot` v2、项目包 v1、P0 request/receipt/l0…l3 的 wire 与含义不变。首版依据只有 `rulePreview` 与 `simplifiedEstimate`，没有 validated/CFD 结果。

## 值契约与 strict codec

- `AnalysisMethod(kind,methodVersion=1)`：airflowPreview / powerEstimate / steadyHeatBalance。`AnalysisConfiguration.payload` 与结果 payload 是 `{kind,value}` 显式联合，request.method.kind 必须匹配配置，result.method.kind 必须匹配 payload 与 basis。
- `AnalysisConfigurationStore(storeVersion=1,projectID,entries)` 每个 entry 是 scenarioID/configuration；scenario/method 不重复。配置含 configVersion=1、可选 roomID/deviceID、acceptedAssumptions、resources。
- Preview 档案包含 profileID/version、baseRadiusMeters、halfAngleDegrees、可选 lengthMeters、pathCount、maximumSegments、UInt32 seed、minimumStrength 和 source；通用档案必须明确接受同 id/version 的 assumption。档案密度不是实际风档。
- Power 配置使用 fixed24HourReference、requestedWindows 和明确 ElectricalPower/basis 的半开分钟时段；basis 是 measuredAverage / declaredScenario / ratedContinuous。显热配置单独以 W/K、degC、m³/s、kg/m³、J/(kg.K)、W 建模；未知仍保留原因，无隐式零、COP 或启停率。
- `ResolvedAnalysisInput` 包含完整不可变 snapshot、所用 configuration 与原样 adoptedAssumptions；requestVersion=1、RunIdentity、method、snapshotHash、computationHash、hashFormat、limits 共同定义一次请求。
- resultVersion=1 的 checks、basis、missingReasons、elapsedSeconds、payload、provenance 独立；freshness 按当前方法 inputHash 派生，persistenceState 由文档事务派生，不混入物理 quality。
- `AirflowPreviewPayload` 只含米制 path points、单位 `1` 的 strength、termination、seat/sample 定性关系及 ruleID。notEvaluated 必须有原因，occluded 必须有 hitEntityID。没有 m/s、温度、PMV 或满意率。

`NativeAnalysisCodec` 先通过独立 strict schema 再做身份/方法/假设/参数/时段语义校验；未知字段、重复键、未知方法与未来版本拒绝解析为有效记录。未知附件可通过包层保留。嵌套 snapshot 经原 `ProjectCodec`；JSONTreeCoding 保留不支持扩展的原始数字 token。

Schemas 从 `Scripts/generate_native_analysis_schemas.py` 生成，嵌入当前生成 snapshot defs，`--check` 检查漂移。生成器每个字段独立复制 schema，检查全部内部 ref；只使用 WireSchema 支持的 anyOf/internal refs 等断言。`Scripts/check_native_analysis_contracts.sh` 输出真实 Swift JSON，再用锁定 Python Draft202012Validator 独立验证；这是开发验证，不是运行依赖。

## 就绪度

`AnalysisReadinessEvaluator` 不改项目。roomView 可显示有效几何并列出无效/未知项；分析维持全项目 projectIntegrity 门槛，仅未采用的 inputPreparation 缺项转为本方法说明。airflowPreview 要一个矩形房间、盒体家具、一个 SingleSplit、一个明确供风方向和已接受档案；风量、回风、送风温度、天气/U/COP 不能被暗中补完或声称守恒通过。当前方案问题带真实 scenario 索引与 UUID；不完整候选的普通准备缺项不污染当前方法。

## Canonical v1 与哈希

格式名 `simunow.native.canonical.v1`，不是 RFC8785。canonical bytes 只用于 hash，不能替代 JSON：

| Tag byte | 值 | 编码 |
|---|---|---|
| 00 | null | 无载荷 |
| 01 / 02 | true / false | 无载荷 |
| 03 | string | UInt64 BE UTF-8 字节数 + UTF-8 |
| 04 | signed integer | Int64 two's-complement BE 8 字节 |
| 05 | unsigned integer | UInt64 BE 8 字节（不能装入 Int64 时） |
| 06 | typed Double | finite IEEE754 binary64 BE；-0 归 +0 |
| 07 | opaque number | UInt64 BE token 字节数 + 原始 UTF-8 token |
| 08 | array | UInt64 BE 数量 + 顺序编码元素 |
| 09 | object | UInt64 BE 数量；键按 UTF-8 排序，依次 string 长度/字节 + value |

UUID 按 schema format 归小写，来源文字不归一。已知模型数字依 schema 解析为整数/Double，不受 1.0/1.00 wire 表示影响；未知扩展数字从不先转 Double。registered payload 使用其注册 schema；unknown payload 用 opaque token。

Golden：`{"a":typed Int64(1),"b":typed Double(-0)}` bytes 为 `090000000000000002000000000000000161040000000000000001000000000000000162060000000000000000`；SHA-256 为 `f687733f0e238dc9116c86e1fa298630971a69c9eabfff1f2912ea0d2985e9ae`（独立 Python hashlib 核对）。

| Hash | 投影 |
|---|---|
| snapshotHash | 全 snapshot，包括未知扩展原 token，作为完整证据 |
| inputHash | project/scenario/method、采用配置/来源/假设；preview 加去名称/northAngle 的几何、供风口 id/position/direction、设备 kind/version/id/roomID、去名称的 seat/sample；power/heat 只采用明确方法配置 |
| computationHash | 同 input 投影 + project/scenario/method 命名空间，缓存不跨方案载荷重绑定 |
| evaluationHash | 固定 runID/inputHash + 评价版本 + 固定评价配置；N4 负责费用具体 schema |

相机、播放/色标/名称不参与 method hash；power 不因风向变，preview 不因费率变。snapshotHash 仍记录原始快照差异。request 在 validating 阶段重新计算全部 hash；不得信任声明的字符串。

## 执行与事件

`LocalAnalysisSubmitting.submit` 返回有限产量 AsyncStream，cancel 幂等。`LocalAnalysisExecutor.method` + `execute(request,progress)` 返回 typed LocalAnalysisExecution；只有实际注册 executor 可运行。生产默认 unavailable client 没有假算法。

actor 最大 2 running / 8 queued，先登记 job 再启动 detached CPU task；accepted→validating→running→可选 progress→checking→唯一 completed/failed/cancelled。sequence 从0递增，每run最多24事件、progress最多16，合法终态不丢。取消排队立即终止，运行取消由 Task.checkCancellation 协作退出；消费者断开触发取消，deinit 释放句柄和continuation。completed 与 checks.failed 可以并存，表示执行完成但方法检查未通过；只有 checks.passed 进入成功缓存。

LRU 最大12份/32MiB，存 calculation payload 而非旧 request/identity；命中包新 runID、当前完整快照与 sourceRunID。client 生命周期内 accepted runID 始终拒绝重复；有限身份表最多65,536份，达到后明确 sessionRunLimit，不悄悄忘记旧 ID。重开进程后的历史冲突仍由不可覆写 artifact 路径拒绝。版本、namespace 不同不命中。

## 项目包与文档值事务

- 配置：`analysis/configuration.json`，≤1MiB。
- 运行：`runs/<lowercase-run-uuid>/native-analysis/input.json`（≤8MiB）、`result.json`（≤2MiB）、`manifest.json`（≤64KiB）。manifest owner=`com.simunow.native-analysis`、artifactVersion=1，含 project/scenario/run ID、request/result version、每文件长度与SHA256。
- manifest 可索引 `evaluations/<64-lowercase-hash>.json`；N4 验证费用语义并追加事务，不修改 input/result 字节。未知/未来评价不能作为有效费用。
- 本 App 已识别配置/native run/评价累计≤32MiB，现有包的4096条目/32深度/64MiB单文件/256MiB总量门槛仍有效。

NativeArtifactCodec 在后台构造/检查不可变 artifact，身份/假设/内容hash必须一致。SimuNowDocument 添加返回完整下一值，使用最新 preservedEntries，无直接 URL 写入；run 路径重复拒绝，不覆盖未知/未来文件，也不自动清理历史。超额保存失败不等同计算失败，旧包保持。

`WorkspaceStore` 的 AnalysisConfigurationStore 纳入原完整值 history，project/config 同一 undo。异步 artifact 附加不进入输入 undo。document.nativeSidefileRevision 是瞬态廉价变化令牌，可驱动后台恢复，不写 metadata。`AnalysisCoordinator` 逐run/scenario/hash/sequence过滤，历史与 persistence 单独保存；N5 负责消费者视图、固定比较/费用恢复与分享。

## 非 AR 能力与开发 probe

仅公开 SwiftUI/RealityKit API：RealityView virtual camera、PerspectiveCameraComponent、互斥 CameraControls.none/orbit/dolly、SpatialTapGesture 与 InputTarget/Collision；完整类型以 macOS15/iOS18 availability 隔离，最低 macOS14/iOS17继续二维。

专用 Debug 构建传 `OTHER_SWIFT_FLAGS='$(inherited) -D SIMUNOW_NATIVE_PROBE'` 可直接启动独立 probe WindowGroup；普通 Mac Debug 的 Developer 菜单也可打开 probe，不改用户文档。N2 采用自管 PerspectiveCameraComponent + .none 实现可复现 reset/focus，系统 orbit/dolly 保留验证入口，不能两套控制同时写相机。实际显示/交互与最低系统运行证据单独记录。

官方 API 依据：[RealityView camera](https://developer.apple.com/documentation/realitykit/realityviewcameracontent/camera)、[CameraControls orbit](https://developer.apple.com/documentation/realitykit/cameracontrols/orbit)、[PerspectiveCameraComponent](https://developer.apple.com/documentation/realitykit/perspectivecameracomponent)。构建核对使用本机公开 SDK 声明；没有导入私有 SDK 模块。
