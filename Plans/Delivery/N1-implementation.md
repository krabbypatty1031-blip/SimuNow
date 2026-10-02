# N1 实现与交接记录

日期：2026-10-03。独立 N1 worktree，基点216b3ad；本文件不替代总status/verification。N1-01/03/04/05已实现并通过自动验证；N1-02已完成可运行非AR probe与两端编译，实际UI证据由根代理补充，最低14/17运行时尚缺。实际N3/N4算法与N2完整房间renderer没有进入此阶段，生产没有test executor。

## 先规划、实现与自审

实施顺序：读真实项目/包/并发接口→独立DTO/schema→公开非AR能力入口→按能力就绪度→不可变解析与canonical/hash→有限actor/缓存→原生侧文件和统一撤销→独立schema/旧契约/两端构建→交叉自审。根README/AGENTS同步本地路线，原P0/v2/package含义和物理硬约束保留。

自审修复：schema字段必须深拷贝以免const/range串改，只生成Codable DTO且检查ref；CameraControls是互斥值，不能当OptionSet组合；SceneBuilder不能运行期if/else切换Scene，专用probe用编译旗标，正常Mac用Developer菜单；结果编码/哈希不占MainActor或阻塞任务actor；后台准备主动传播取消；未知几何仅阻断采用它的方法；项目/config共享undo，撤销到无配置要移除已识别侧文件；删除候选同步删除配置且undo恢复；文档事务保留原registry/limits与所有未知附件；不变配置不改变侧文件revision；结果不能突破请求资源上限；所有已接受runID在会话内防重复，有限身份表满时明确拒绝。

## 文件与公开接口

| 模块/文件 | 实际API和下游接入 |
|---|---|
| Core/Analysis/AnalysisConfiguration.swift | AnalysisKind/Method、三种typed配置、假设、资源限制、ConfigurationStore；Preview默认值只是明确可接受的显示档案，resolver不自动接受 |
| Core/Analysis/AnalysisModels.swift | Request/Result/Event、PreviewPath/Point/TargetRelation、Power/Heat payload、Manifest、Readiness/Issue；各模型Foundation-only/Sendable |
| Core/Analysis/AnalysisEvidence.swift | ComparisonSnapshot/RunReference与RecommendationEvidence固定证据；N4/N5完善其专用记录codec/schema |
| Core/Analysis/NativeAnalysisCodec.swift | encode/decode Request/Result/Event/Manifest/Configuration，strict schema→语义→原ProjectCodec快照；bundle schema只读缓存 |
| Core/Analysis/AnalysisReadinessEvaluator.swift | evaluate(project:scenarioID:capability:configuration:additionalIssues:)；view可显示部分有效几何，preview保持完整性，只忽略未采用准备缺项；显式aggregate power/heat不要求未采用几何 |
| Simulation/LocalAnalysis/AnalysisInputResolver.swift | request(project:scenarioID:method:configuration:runID:additionalIssues:)；validate(request)重算hash；AnalysisHasher.sha256/hashes/evaluationHash |
| Simulation/LocalAnalysis/AnalysisCanonicalizer.swift | NativeCanonicalValue + bytes/value，v1 tag格式、schema区分typed/opaque数字、UUID小写/-0、循环取消检查 |
| Simulation/LocalAnalysis/LocalAnalysisClient.swift | LocalAnalysisSubmitting.submit/cancel；Executor.method + execute(request,progress)→LocalAnalysisExecution；actor注册真实executor，默认unavailable；statistics/shutdown |
| Visualization/RealityKit | RendererCapabilities.current；RealityKitCapabilityProbeView，public SDK、virtual相机、自管/orbit/dolly互斥、对象点选与非手势按钮 |
| Workspace/Analysis/AnalysisCoordinator.swift | start(request,persist:)、stop/restore/result；匹配run/scenario/hash/sequence，后台构造artifact，persistence与结果独立；事件游标拒绝乱序/重复/foreign/多终态 |
| Workspace/Analysis/AnalysisReadinessView.swift | 文字辅助的blockers/warnings显示，可被N3/N5真实工作流使用 |
| Workspace/Documents/NativeAnalysisArtifacts.swift | NativeArtifactCodec.make/decode/read；doc.analysisConfigurationStore/updatingAnalysisConfiguration/appendingNativeAnalysis/applyingWorkspaceState；不可变artifact无public任意构造器 |
| Workspace/Documents/SimuNowDocument.swift | nativeSidefileRevision瞬态UUID变化令牌；replacement保留自定义registry/包limits；无metadata新键 |
| WorkspaceStore/WorkspaceDocumentView | localAnalysisClient注入（包含iOS独立导入会话）、prepareLocalAnalysis后台输入/哈希、updateAnalysisConfiguration/replaceProjectAndAnalysis统一完整值undo，config侧文件外部同步；结果附加不load/清空undo |
| Protocols/Schemas + Core Resources | 5份独立schema；native-analysis-v1.md完整tag、hash投影、边界、事件/目录/预算 |
| Scripts | generate_native_analysis_schemas.py --check、check_native_analysis_contracts.sh、validate_native_analysis_contracts.py；标准check_contracts.sh已纳入native drift与真实输出独立验证 |
| Apps | SIMUNOW_NATIVE_PROBE专用WindowGroup；Mac Debug Developer→Open N1 RealityKit Probe。正常release没有probe菜单或假的数值入口 |

后续N2必须复用CoordinateTransform与capabilities，不为RealityKit提高最低版本；N3实现真实LocalAnalysisExecutor并由入口注册共享client，不复制DTO；N4按固定时间/来源配置计算，费用独立evaluationHash；N5通过当前document binding调用完整值事务并用nativeSidefileRevision后台重载历史，不从计算actor直接写打开的URL。

## 验证证据

工具链：Xcode27.0 / 27A266a，Swift6模式，macOS14/iOS17 deployment target。开发Python沿用已有锁定环境；未安装引擎、关闭sandbox或新增App运行依赖。

| 命令 | 结果/证据 |
|---|---|
| Scripts/check.sh test | 105项Swift共享测试通过（原83+新增22），另Extension模块2项；N1/native-contracts.log记录最终同一套测试 |
| Scripts/check_native_analysis_contracts.sh | 105 Swift通过；15真实Swift DTO文件由独立jsonschema4.26.0验证，6拒绝变异与字段独立性断言通过；Artifacts/N1/native-contracts.log |
| Scripts/check.sh contracts | 39 Python、105 Swift + Extension2、2项目/快照及28错误兼容交换通过；原包metadata独立校验、新native校验通过；Artifacts/N1/contracts.log |
| Scripts/check.sh mac / ios | 最终正常App编译结果写Artifacts/N1/{mac,ios}-build.log；运行证据单列，编译不是交互验收 |
| 专用probe两端Debug构建 | 已成功；Artifacts/N1/probe-{mac,ios}-build.log。独立bundle ID验证副本，不关闭用户已有App或未保存文档 |
| git diff --check、schema --check | 无whitespace/资源漂移；精确提交仅N1文件，不包含复制的既有Plans和用户scheme |

所有测试executor、人工功率/ρ/cp与示例结果只存在于Tests，证明实现和契约，不证明现实预测精度。

## V-N1 案例覆盖

| 案例 | 自动证据/人工边界 |
|---|---|
| 01 | nativeDTOsRoundTripAndIndependentSchemaExport三种方法，typed known/unknown、15份真实JSON |
| 02 | nativeCodecRejectsFutureMismatchExtraMissingAndWrongUnits、独立6变异，非finite与空原因拒绝 |
| 03 | 原83共享回归、39Python与真实双向交换，P0/v2/包保持 |
| 04 | 独立Draft202012Validator、生成器漂移/ref检查；真实Swift输出 |
| 05 | 两端probe构建通过；现代端实际显示/选择/相机由根代理补证，14/17尚notAvailable，不能合并为全通过 |
| 06 | nativeReadinessSeparatesUnusedPhysicsFromIntegrity，未知功率/COP/flow/density/供风温度/天气/热工/return不误阻断 |
| 07 | direction_unit具体路径阻断，原几何/ID/边界回归不放宽 |
| 08 | 多房间/未知家具明确unsupported、opaque原token保留；当前Usage没有可注册占用扩展字段，不能编造该已实现类型 |
| 09 | 功率时段/basis缺项、热配置检查；nativeExplicitAggregatePowerDoesNotRequireUnusedGeometry |
| 10 | 原selectedScenario remap回归 + 方法snapshot独立/深层修改测试；全项目integrity仍严格 |
| 11 | canonical golden bytes+独立hashlib SHA256，opaque大数字、UUID大小写/-0、数组顺序 |
| 12 | 方法字段hash测试：名称/方向/费用/功率，配置全字段采用；相机从不进入snapshot/config DTO |
| 13 | artifact保存/FileWrapper重开 + 原P2真实磁盘重开；snapshotHash与未知原token、深层修改隔离 |
| 14 | request snapshotHash/inputHash变造拒绝；client validating重新核对，不信字符串 |
| 15 | 排队/运行/重复取消、消费者取消与continuation释放；2运行+8排队后全取消 |
| 16 | completed/failed/cancelled唯一终态、throw、checks.failed不缓存；actor串行决定完成/取消边界 |
| 17 | 200次progress调用只产≤16，≤24事件，游标过滤foreign/乱序/重复/多终态 |
| 18 | 未注册/重复runID/队列超限明确拒绝；没有生产fake executor |
| 19 | 缓存命中包新identity/sourceRunID；namespace含project/scenario/method，不跨候选载荷重绑 |
| 20 | 13份LRU保留12、字节1上限不缓存、checks.failed/取消不缓存；方法版本key独立 |
| 21 | 同步CPU大循环实际不在main thread，actor取消仍可达，20次coordinator创建/停止弱引用释放；真实窗体20次观察仍由N2/N5 runtime证据补足 |

V-N5-01…05的基础artifact/附件/完整值失败行为已覆盖：FileWrapper关闭重开、碰撞、损坏/未来manifest保留、容量失败旧值不变、绑定undo/redo不丢opaque文件。完整消费者保存/费用/比较/系统浏览器重开与多窗口交互留N5接入验证，不把基础单测当产品闭环。

## 仍需记录的限制与选择

- 本阶段没有真实气流算法、热估算或推荐，只有接入真实executor的基座；生产未注册方法不可用。
- 非ARprobe不是N2完整renderer，N2要验证自己的reset/focus/选择/手势、实际三维坐标和旧系统完整二维。
- macOS14/iOS17运行时当前不可用；availability/最低target编译通过不代表最低系统运行成功。
- Config/artefact事务只更新document值；DocumentGroup负责原子协调保存。保存失败必须单列，不能宣称已写盘。
- 身份防重表有65,536会话上限，达到明确sessionRunLimit；从不偷偷忘记旧ID。包budget32MiB/8MiB/2MiB/64KiB仍由持久化门槛执行。
- CostEvaluationRecord/ComparisonRecord专用codec/schema与append事务在N4/N5实施；现有manifest允许受控evaluation路径，未知内容不当有效费用。
- 默认方法配置的profile/source是内部显示假设；N3需验证profile/version支持并持续标注几何规则，不按m/s/T/舒适解释。
