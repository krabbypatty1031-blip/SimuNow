# N1：本地分析基座与能力验证

版本：详细执行稿v1，2026-10-03。状态：N1-01/03/04/05代码已整合；N1-02实际平台验收部分完成。前置P0/P2代码；不以P1安装为前置。

## 阶段目标与交付边界

完成可供N2–N5接入的值契约、按能力就绪度、输入解析/哈希、本地client、缓存和小型run包边界；实际验证两端非AR三维入口。N1可以用test executor验证事件，但生产App继续把未注册算法显示为不可用，不返回占位温度/能耗。

实施前读[AI执行规范](../References/10-ai-execution-guide.md)、[验收案例](../References/11-native-acceptance-cases.md)、[数据计划](../References/04-data-contracts.md)、[方法规格](../References/07-native-method-spec.md)。实际接口映射见[N1交接](../Delivery/N1-implementation.md)，本页执行清单保留任务要求；通过情况以[逐项台账](../Delivery/native-acceptance-status.md)为准。

## 现有代码接入点

| 已有文件 | 开工需要确认的行为 |
|---|---|
| [SimulationClient.swift](../../Packages/SimuKit/Sources/SimuSimulation/SimulationClient.swift) | P0请求只有identity/fidelity；保留原协议和未配置client |
| [SimulationModels.swift](../../Packages/SimuKit/Sources/SimuCore/SimulationModels.swift) | RunIdentity可复用；旧RunReceipt没有数值结果 |
| [ProjectCodec.swift](../../Packages/SimuKit/Sources/SimuCore/Project/ProjectCodec.swift) | capture只复制数据；encodeSnapshot验证结构，不证明可分析 |
| [ValidationTypes.swift](../../Packages/SimuKit/Sources/SimuCore/Project/ValidationTypes.swift) | projectIntegrity和inputPreparation不能混用 |
| [PhysicsRule.swift](../../Packages/SimuKit/Sources/SimuCore/Project/PhysicsRule.swift) | port_topology/热工缺项与direction_unit等错误不同 |
| [WorkspaceStore.swift](../../Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift) | project私有写入、完整值undo、revision；captureSelectedInput有原有严格门槛 |
| [SimuNowDocument.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Documents/SimuNowDocument.swift) | preservedEntries私有写入、包预算、天气哈希缓存 |
| [WorkspaceDocumentView.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Documents/WorkspaceDocumentView.swift) | document binding权威、原回调只发布project/metadata，需新侧文件通道 |

## 任务顺序与文件归属

| ID | 前置 | 首要交付 | 可独立推进 |
|---|---|---|---|
| N1-01 | P2 | 独立本地DTO/schema/codec与根指南同步 | 与N1-02并行 |
| N1-02 | P2 | 实际RealityView capability与回退证据 | 不依赖算法 |
| N1-03 | N1-01 | 方法就绪度和修复定位 | N1-04可同时做 |
| N1-04 | N1-01 | ResolvedInput与snapshot/input/computation/evaluation四类hash | 契约冻结后开始 |
| N1-05 | N1-03/04 | client、事件、取消、缓存、artifact接口 | 合并后统一验证 |

Core/Analysis、Protocols与WorkspaceStore公开接口指定一个整合人；后续Agent不能自建第二份DTO。N2依赖N1-01…03，N3完整执行依赖N1-01…05。

## N1-01：冻结本地契约、codec与schema

**输入**：现有v2/包v1/P0边界；执行规范中的字段表。**输出**：可编译值类型、可校验JSON、协议文档、至少一份request/event/result真Swift输出。

**新增/修改位置**：Core/Analysis下AnalysisMethod、AnalysisConfiguration、AnalysisModels、NativeAnalysisCodec；Protocols/native-analysis-v1.md和独立schema；Core资源只添加本地schema；Scripts/check_native_analysis_contracts.sh；根README/AGENTS更新产品描述和阅读N阶段。保留原生成文件与P0类型。

执行步骤：

- [ ] 逐项对照执行规范定义DTO；区分resultBasis、executionState、checks、freshness、persistenceState，不用一个passed包办。
- [ ] 冻结三种kind及version1；费用属于power结果评价；roomView不创建run。payload联合显式约束kind，不能用默认分支解未知方法。
- [ ] 复用Core单位/SourceRecord/UncertaintyBounds；新增Analysis专用单位值在独立文件定义，不改生成DomainModels。配置中的假设必须有id/version/source/意义。
- [ ] 用受支持的schema断言构造完整内部defs；嵌套snapshot从已有生成schema组合并检查资源漂移。不要使用WireSchema不支持的oneOf/外部ref/通用date-time。
- [ ] NativeAnalysisCodec先做结构/版本/schema，再做本地语义校验，嵌套snapshot走ProjectCodec；缺失值和不支持方法返回明确错误。
- [ ] 写Swift输出→独立Draft2020-12Validator验证入口，沿用SIMUNOW_PYTHON开发环境；App运行不调用Python。
- [ ] 更新Protocols索引和根指南：P2代码完成、N路线待实现、外部复核可选；保留原物理硬约束。

**验证**：V-N1-01…04。至少覆盖round-trip、方法/payload不匹配、未来版本、未知字段、单位错误、非有限数、missing无原因、大数字扩展保留。命令：test、native契约检查；涉及共享模型再contracts，两端新增调用再mac/ios。

**完成清单**：DTO全为Sendable/值语义；没有RealityKit/CryptoKit进入Core；协议与实际Swift JSON一致；P0/v2旧夹具仍通过；下游可根据同一schema实现，不留“payload自行设计”。

## N1-02：RealityView非AR能力验证

**输入**：当前SDK、macOS14/iOS17最低配置、已有坐标转换。**输出**：小型可运行renderer验证、RendererCapabilities值、平台矩阵和操作证据。

**位置**：Visualization/RealityKit/RendererCapabilities.swift与RealityKitCapabilityProbeView.swift；Apps只注入必要能力；验证入口明确开发用途，N2接替后移除测试按钮。

执行步骤：

- [ ] 本机SDK核对RealityView、virtual camera、camera controls、选择手势和材质API；记最低版本和实际工具链，禁止从网页示例推定全部平台可用。
- [ ] 以`#available(macOS 15, iOS 18, *)`隔离完整renderer类型和构造；旧系统返回二维能力，连类型引用都不能泄漏availability。
- [ ] 用非AR虚拟相机画1个米制盒体、地板和一个可选择对象；不请求摄像/世界追踪/RoomPlan权限。
- [ ] 先验证公开camera controls orbit/dolly；若不能支持重置/聚焦，在N2采用单一自管相机策略，记录选择，不能同时两套控制互相覆盖。
- [ ] Mac和iPhone/iPad各验证打开、旋转、缩放、选择、关窗/离页；不把编译成功当截图/交互成功。
- [ ] 核对14/17分支可编译并运行二维；没有相应运行时记录未验证，不提高最低版本绕过。

**验证**：V-N1-05、V-N2-07/08。保存机型/OS/SDK、命令、截图、权限与关闭观察。**完成清单**：两端非AR有实际证据；旧分支没有未保护调用；生产没有空按钮/测试温度；不新增私有API或重型依赖。

## N1-03：按方法就绪度与字段修复

**输入**：project、selectedScenarioID、包相关问题、AnalysisConfiguration。**输出**：四种capability的AnalysisReadiness，带字段定位/理由；不修改项目。

**位置**：Core/Analysis/AnalysisReadiness.swift；Simulation/LocalAnalysis/AnalysisInputProjection.swift；Workspace/Analysis/AnalysisReadinessView.swift。纯值校验可放Core，投影解析/调度留Simulation，避免Core反向依赖。

执行步骤：

- [ ] 结构decode失败仍拒绝；语义修复项目可浏览有效几何并列不可显示对象。执行分析要求projectIntegrity通过，保留P2保存门槛。
- [ ] 捕获所选方案时直接使用ScenarioSnapshotBuilder，再执行本方法检查；不要调用旧captureSelectedInput并把所有inputPreparation问题当阻断。
- [ ] roomView检查几何、尺寸、身份与边界；无设备/热工数据仍可显示。
- [ ] airflowPreview要求单房间矩形、盒体家具、单台支持设备、明确一个有效supply、有限且单位方向及合法墙面内向条件；return/送风温度/风量/U/COP未知只列未采用项，不虚构质量平衡通过。
- [ ] 未知几何可能影响路径则阻断预览；未使用的占用扩展可列excludedEntities警告，必须保留原值。多个房间/设备不能静默只算第一项。
- [ ] powerEstimate检查明确功率basis和时段，不依赖方向；heatBalance按N4配置检查UA/温差/交换/显热，不提前要求湿度/MRT。
- [ ] 把问题路径映射回真实scenario索引、entity UUID和表单；选中其他不完整候选不污染当前方案检查。

**阻断分类表**：

| 情形 | 查看 | 气流 | 估算 |
|---|---|---|---|
| 未知U/COP/送风温度/天气 | 可查看 | 可预览 | 仅缺该方法必需输入时阻断 |
| supply方向零/非单位或坐标非法 | 对象标无效 | 阻断相关分析 | projectIntegrity错误仍需修复 |
| 多设备/未知家具几何 | 尽可能查看并说明 | unsupported | 功率显式aggregate方式另验 |
| 未来配置/未知方法 | 项目可查看 | 不解析该配置 | 不用默认值替代 |

**验证**：V-N1-06…10。**完成清单**：missing不转0、warning不冒充passes；ProjectValidator规则不被全局放宽；当前能力和原严格准备报告可同时查看。

## N1-04：解析假设、规范化与哈希

**输入**：有效snapshot、明确接受的配置、方法版本。**输出**：不可变ResolvedInput及snapshotHash/inputHash/computationHash/evaluationHash，详见执行规范。

**位置**：Simulation/LocalAnalysis/AnalysisInputResolver.swift、AnalysisCanonicalizer.swift、AnalysisHasher.swift；Tests/SimuCoreTests/AnalysisHashTests.swift。

执行步骤：

- [ ] 解析registered payload和SI量，保留原source；unknown只在用户明确接受配置假设时得到方法值，原snapshot仍unknown。
- [ ] 按方法建字段投影清单；preview纳入几何/风口/关注点/规则配置；power纳入功率basis/时段；cost单独含费率/币种。
- [ ] 规范化格式、UTF-8键序、UUID大小写、有限Double/-0、数组顺序与未知数字token规则写入协议，保存golden字节与hash。
- [ ] CryptoKit仅在Simulation实现SHA-256；hashValue不持久化，不能以当前时间/随机runID充当输入hash。
- [ ] 校验request声明的hash与重新计算一致，输入变造直接失败；不要只信调用方字符串。
- [ ] 测源快照拷贝后深层修改不影响run，逐字段证明相机/名称/无关参数的失效策略。

**验证**：V-N1-11…14，包括大数token保留、配置/seed/方法版本变化、角度不改功率、费率只改evaluation、同字节重开重hash。

**完成清单**：每个hash的投影有可审查表和测试；规则参数都纳入key；结果缓存不跨方案复用实体载荷；字符串规范化不误删来源意义。

## N1-05：本地执行、事件、取消、缓存和artifact边界

**输入**：N1-03/04通过的request、可注入executor。**输出**：LocalAnalysisClient actor、状态事件、有限缓存、artifact codec与文档添加接口；N5完成UI级保存恢复。

**位置**：Simulation/LocalAnalysis/{LocalAnalysisClient,LocalAnalysisExecutor,AnalysisCache}.swift；Core/Analysis事件/manifest值；Workspace/Documents/NativeAnalysisArtifacts.swift；Workspace/Analysis/AnalysisCoordinator.swift。

执行步骤：

- [ ] 实现submit/cancel；重复runID请求拒绝。算法注册表首版只有实际已实现executor，未注册明确unsupported。
- [ ] actor建立job表后再启动任务，避免cancel发生在登记前；显式非MainActor执行纯算法、保存任务句柄、传播取消，设置全App2运行/8排队。
- [ ] 事件accepted→validating→running→checking→唯一终态；sequence从0递增。限制progress频率/数量，终态不能丢。schema/identity入参错误可在accepted前throw。
- [ ] 在阶段/路径循环检查取消；排队取消移除，运行取消请求协作退出；重复cancel幂等。client释放/消费者断开终止对应job和continuation。
- [ ] 用FakeClock和test-only executor验证调度，不在真实App注入伪算法；consumer只接受匹配run/scenario与更新sequence。
- [ ] 缓存按方法namespace和computationHash；12份/32MiB的LRU，命中生成新identity和cacheHit记录；失败/取消载荷不作为成功cache。
- [ ] 构造immutable artifact数据：input.json/result.json/manifest.json位于runs/<runID>/native-analysis；manifest owner明确、长度/hash校验，input/result身份一致；文件索引允许受控evaluations相对路径，具体费用codec由N4-02补齐，未知记录不当有效评价。
- [ ] 新Document方法从最新preservedEntries构造下一值并预检包预算；不加metadata键、不直接写URL。unknown runs条目/未来manifest保留，碰撞不覆写。
- [ ] 协调器处理current/stale/history/persistenceState，保存失败保留内存结果并说明；给N5配置撤销/侧文件外部更新预留真实接口，不用load清空undo。

**验证**：V-N1-15…21、V-N5-01…05；包括cancel-before-start、cancel-at-finish、乱序重复、窗口关闭、cache身份、manifest损坏/未来版、容量失败旧包不变。

**完成清单**：Swift6严格并发通过；无uncheckedSendable；actor不被CPU循环阻塞取消；无多writer；没有“succeeded但未注册算法”；N3/N4能实现一个executor接入而不重写client。

## 阶段交接与最终审视

- [ ] N1-01/03/04/05的纯值和失败路径均有证据；N1-02实际平台结果单独列明。
- [ ] 新方法/配置/schema资源与协议索引一致；旧contracts回归，test与受影响mac/ios构建完成。
- [ ] 比对原v2/包/P0含义；inputPreparation、方法检查与物理验证没有混成一个状态。
- [ ] status/verification记录每任务，不把“详细计划完成”记成“代码完成”。
- [ ] 向N2交接capability与输入检查，向N3/N4交接request/executor/result，向N5交接artifact/document/coordinator接口。

最小完成门槛是可接入实际executor的本地链路，不要求实现N3规则或N4估算；N1测试输出只作为契约证据。缺平台运行条件可继续其他项，但N1-02验收保持未通过/未验证。
