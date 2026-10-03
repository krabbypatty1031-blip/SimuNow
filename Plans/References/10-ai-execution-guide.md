# N1–N5 AI执行与交接规范

更新：2026-10-03。本页与N1–N5详细工作包记录实施约定；已实现接口以[N1交接](../Delivery/N1-implementation.md)、[N2交接](../Delivery/N2-implementation.md)、[N3交接](../Delivery/N3-implementation.md)及Protocols为准。新增类型名/文件名为实施约定；若源码中已有等价实现，先复用并在交接说明映射，不创建重复类型。当前实施状态见[状态](../Delivery/status.md)和[逐项台账](../Delivery/native-acceptance-status.md)。

## 1. 开工顺序与边界

1. 读Plans/README、Delivery/status、相应阶段、本页和[验收案例](11-native-acceptance-cases.md)。
2. 读阶段列出的已有源码，记录实际public接口、actor隔离与文档绑定。
3. `git status --short`确认已有工作；只修改本任务归属文件，保留Pitch、scheme和其他任务内容。
4. 写出本任务3–8步实施清单，列公开接口、依赖任务和需要复用的P2能力。
5. 先最小数据/纯函数和相关验证，再UI连接；完成后按任务的“自审与完成门槛”检查。
6. 更新status/verification中的本任务事实，接口/范围选择变化更新ADR。代码、运行、模型验证分别记录。

详细规划已完成；用户最新持续目标为按N1→N2→N3→N4逐类实施，包括N4全部Should任务。N5、PDF、ComparisonRecord和发行候选保留后续计划，本次不实施。N1～N4共21个工作项、72个验收案例按实际证据逐项核对；不能因范围缩小而把这四阶段已有取消、文档替换或性能缺陷推到N5。新路线优先于旧引擎计划；实施授权不包含Push或公开发布。

## 2. 接口唯一归属

| 位置 | 归属与内容 | 禁止内容 |
|---|---|---|
| SimuCore/Analysis | Codable/Equatable/Sendable DTO、分析问题、方法、结果、配置与比较证据 | SwiftUI、RealityKit、CryptoKit、磁盘IO |
| SimuSimulation/LocalAnalysis | client/actor、解析配置、CryptoKit哈希、有限缓存与调度 | MainActor视图、FileWrapper、私有平台路径 |
| SimuSimulation/AirflowRules | 纯规则场、碰撞路径、关注点关系 | Entity物理、舒适/CFD标签 |
| SimuSimulation/ThermalEstimate | 用电、费用、显热与情景比较 | 隐式COP/启停率、年度外推 |
| SimuSimulation/DecisionRules | N5纯建议规则，输入固定分析结果 | 报告内重新计算或不可追溯评分 |
| SimuVisualization/RoomScene与RealityKit | descriptor、相机、材质、选择和路径显示 | 热量/成本/建议算法 |
| SimuWorkspace/Analysis与Comparison | 工作流、就绪度展示、当前run选择、方案操作 | 第二份项目权威、直接改ProjectDocument私有状态 |
| SimuWorkspace/Documents | 分析侧文件与原生文档事务 | 从分析actor直接写正在打开的URL |
| SimuReporting | 固定证据快照、匿名化与导出 | 修改结果或重算指标 |

现有Tests/SimuCoreTests依赖Core/Simulation/Visualization/Workspace，可先增加相关测试文件。Reporting测试若需要新增target或测试依赖，只添加该依赖；不改业务依赖方向、不自动新增UI测试target。包源码不改pbxproj；App资源/配置变化维护generate_project.py并保留既有scheme。

## 3. N1冻结的值契约

| 名称 | 最少字段与语义 |
|---|---|
| AnalysisMethod | kind=airflowPreview/powerEstimate/steadyHeatBalance；methodVersion正整数；resultBasis=rulePreview/simplifiedEstimate |
| AnalysisConfiguration | configVersion、roomID/deviceID、方法专用payload、acceptedAssumptions、资源设置；不是现有项目物理输入 |
| AnalysisConfigurationStore | storeVersion=1、projectID、scenarioID索引的method配置；对应analysis/configuration.json容器，重复scenario/method拒绝 |
| AnalysisIssue | code、severity、scope、entityID、fieldPath、message、repairAction；阻断明确到某能力 |
| AnalysisReadiness | capability、eligible、blockers、warnings、unsupportedEntities；不能直接等于inputPreparation |
| ResolvedAnalysisInput | 完整ScenarioInputSnapshot、解析后方法输入、配置/规则版本、实际采用假设；let/值语义 |
| LocalAnalysisRequest | requestVersion=1、RunIdentity、method、resolvedInput、snapshotHash、computationHash、资源上限 |
| LocalAnalysisEvent | eventVersion=1、runID/scenarioID、sequence、stage、payload；accepted到terminal序列单调 |
| LocalAnalysisResult | resultVersion=1、identity/method、checks、basis、assumptions、missingReasons、elapsed、typed payload |
| AnalysisArtifactManifest | artifactVersion=1、owner标识、文件相对名/长度/hash、request/result版本；不复用metadata键 |
| ComparisonSnapshot | comparisonVersion、comparisonID/projectID、固定run/方法版本、comparisonContextHash、可比较项/不可比较原因；不读取实时编辑对象 |
| CostEvaluationRecord / ComparisonRecord | 独立版本/owner、父run引用及固定评价/比较配置、payload；由N4/N5补充具体schema与保存，不改原input/result |
| RecommendationEvidence | RuleID/version、runID/实体/字段、条件和文字；只有已存在证据才能生成建议 |

`roomView`属于查看能力，不创建假的分析run。费用是powerEstimate结果的独立评价，不增加无必要的重复求解任务。测量/经验证求解的等级预留明确扩展，但首版构造器不可自行升级至validated。

请求/结果采用kind+payload明确联合；unknown method/version保留为不支持或拒绝该分析记录，不能decode成默认预览。missing必须有code/reason。路径坐标始终米制Z-up，pathStrength单位为`1`；输入和结果不能携带Entity、FileWrapper、URL安全书签或UI闭包。

## 4. 兼容与schema约定

- ProjectDocument v2、ScenarioInputSnapshot v2、包v1、P0 request/receipt和l0…l3含义不变。
- 独立文件：Protocols/native-analysis-v1.md及local-analysis-request/event/result、analysis-artifact-manifest、analysis-configuration schema（涵盖Store容器及配置defs）。名称在N1-01最终冻结后各阶段遵循同一份。
- WireSchema当前支持内部`#/$defs/`、anyOf/allOf/if条件等子集，不支持任意远程ref/oneOf/通用date-time。新schema使用已支持断言；版本、方法分支用const+anyOf/if约束。嵌套快照的defs从现有生成资源组合/校验漂移，不手工复制一份逐字段模型。
- Swift的NativeAnalysisCodec校验新结构与语义，嵌套项目/快照仍经ProjectCodec。独立Python jsonschema验证真实Swift输出；Backend不需要重实现本地算法。扩展共享项目字段时仍同步生成清单、Swift/Python、schema和迁移。
- 费用评价使用独立cost-evaluation schema，固定比较使用comparison-record schema，在N4-02/N5-02补齐Swift/独立schema校验；旧App不支持的记录仍作为opaque附件保存。
- 包metadata拒绝未知键。新的`analysis/configuration.json`与`runs/<run-id>/native-analysis/`是独立侧文件；仅识别有本App owner/version的记录。未知目录/未来版本无损保留，不能升级为有效run或自动删除。
- 费用记录在`runs/<run-id>/native-analysis/evaluations/<evaluation-hash>.json`；加入时只扩充该run manifest的文件索引，不改input/result字节，明确appendEvaluation事务，不绕过重复run拒绝。固定比较在`analysis/comparisons/<comparison-id>.json`，ComparisonRecord保存owner/version、bodyHash（排除此字段的canonical body）及被引用run/input/evaluation hash。两者重复身份同内容可复用、不同内容拒绝，关闭重开校验引用与内容，不读取实时对象替换旧证据。

## 5. 身份、缓存和新鲜度

| hash | 内容 | 用途 |
|---|---|---|
| snapshotHash | 完整快照的受控规范化wire字节，含未知扩展token | 证据完整性，核对保存与重开 |
| inputHash（RunIdentity） | 当前方法真正采用的解析输入、来源/假设与版本，含项目/方案/实体身份 | 此方法结果相对当前输入是否过期 |
| computationHash | 方法计算投影+算法/配置/精度/seed；命名空间限定projectID/scenarioID/method | 当前方案内重复输入缓存；首版不做跨方案载荷重绑定 |
| evaluationHash | run/inputHash+时段、电价/币种、评价方法版本 | 电费/比较独立失效 |

规范化格式标为`simunow.native.canonical.v1`，不是声称实现RFC8785。N1-04采用独立类型标记序列：null/Bool、UTF-8 string、数组、对象、已解析整数/Double、opaque数字各有不同tag；变长内容前写UInt64 big-endian字节长度，容器写元素数，对象按UTF-8键序编码key/value。已解析有限Double用IEEE754 binary64 bitPattern的big-endian8字节，-0归+0；整数使用有符号/无符号明确类型与固定字节策略，UUID作为小写字符串。opaque数字tag后保存原token UTF-8，不能先转Double。schema字段与扩展袋使用不同编码入口，避免同一数字随机落到两种tag。

协议须列tag字节表与完整golden字节/hash，canonical数据仅用于hash，不替代JSON文件。snapshot入口遍历已解析快照/registered payload和unknown扩展，不能直接使用JSONEncoder输出字典顺序。键序/已解析1.0与1.00的表示不影响hash，unknown原始token差异可以影响完整snapshotHash。先固定格式再生成hash；精度/tag策略变化必须升hashFormat版本。

inputHash排除名称、相机、色标、播放时间和与此方法无关的数据；来源/假设纳入以保证证据有效。powerEstimate不因风向改变失效；费用改变只使评价失效；airflowPreview不因电价改变失效。snapshotHash仍可随无关原始输入改变，新证据必须指向实际保存的完整快照。

缓存只存计算载荷与其计算来源标识，不存可直接复用的RunIdentity/request。命中后以新请求runID及当前完整snapshot封装证据，记录cacheHit/sourceRunID，检查相同method/version/namespace。不得把另一方案的sample/device UUID贴进当前载荷。

## 6. 并发、状态与预算

推荐协议：`submit(LocalAnalysisRequest) async throws -> AsyncStream<LocalAnalysisEvent>`、`cancel(runID: UUID) async`；已接受后的算法失败通过唯一terminal事件返回。每个工作区持有协调器和当前订阅；client由入口注入。DTO层不保存重复的current/stale状态：freshness由当前方法inputHash派生，persistenceState由文档事务回执派生；历史快照可保存导出时状态但不是实时权威。

执行状态为accepted→validating→running→checking→completed/failed/cancelled；不借用meshing描述规则计算。Actor负责job表和状态，纯计算显式在非MainActor任务执行；若用Task.detached，保存句柄并主动传播取消/释放，不假设自动继承生命周期。阶段/路径循环检查Task.checkCancellation，不在MainActor中跑计算后再切actor。

事件不传逐点结果或每帧日志。控制每run最多24个事件，progress最多16次，终态必送；可用有限产量的AsyncStream默认队列，不能用bufferingNewest悄悄丢accepted/terminal。消费者丢弃错run/旧sequence，onTermination取消对应工作；完成后释放continuation/句柄。

初始限制：全App最多2个运行job、最多8个排队；每工作区只有一个交互预览在途，编辑防抖250ms且取消前次；缓存最多12份或32MiB，先达到者触发LRU；路径最多64条×128段。请求超限拒绝或由用户已选择的配置降低，不能静默改写分析输入。

原生run建议input≤8MiB、result含路径≤2MiB、manifest≤64KiB；配置Store≤1MiB，单费用评价/比较记录≤256KiB；本App已识别配置/run/费用/比较记录累计≤32MiB。超额分析可完成但不能宣布已保存；保留旧文件和编辑输入，明确“结果未保存”。不得自动删未知附件或被报告引用的历史。最终预算在N3/N5实測并记录，包既有上限继续有效。

任务成功、方法checks、resultBasis、freshness和persistenceState独立。UI只把当前hash匹配、此方法检查通过的结果显示为当前；旧run可以历史保存，保存时标明原scenario/hash。关闭工作区取消订阅、预览任务与展示动画，不泄漏窗口/store。

## 7. 持久化与P2集成

已有WorkspaceStore.project为private(set)，replaceProject/replaceScenarios/applyTemplate/undo/load已具备事务。新增分析配置与run记录经独立文档事务更新preservedEntries，禁止变造metadata键或用load重置整个项目来“刷新结果”。

分析配置是显式用户选择，纳入撤销协调；必须扩展完整工作区检查点或建立统一事务协调，不能让项目与配置各有不同步undo栈。选择/相机不进输入undo；异步结果加入和保存状态不构成用户输入撤销操作。外部文档更新重新载入配置/历史、失效旧任务，不能只监听project/metadata而漏掉侧文件。

所有异步文档更新先核对文档实例/项目/方案/当前内容revision；合并到最新preservedEntries，保留期间新导入附件。旧run有其归属，可以加入历史但不自动成为当前结果；目标方案已删除时以orphaned历史提示，不覆写或复活方案。

## 8. 完成与阻断处理

每任务交接至少包含：改动文件、公开接口映射、验收案例ID与结果、命令/日志、实际平台运行范围、剩余阻断。没实现功能保持不可用；临时test client不可进入生产依赖注入。

缺模拟器/最低系统时，继续不依赖它的纯算法/文档工作；实际平台项记录未验证，不能标整个验收通过。公开接口有改变先修更新调用方/契约/测试再交接；不留“其他Agent自行适配”。多Agent仅在用户授权后使用，接口文件指定整合人、独立worktree，合并后重新验证受影响路径。
