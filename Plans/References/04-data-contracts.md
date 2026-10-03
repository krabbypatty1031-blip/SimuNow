# 数据与文件契约

## 已有协议与新计划边界

P2 已实现 ProjectDocument v2、ScenarioInputSnapshot v2 与 `.simunow` 包 v1，见 [项目契约](../../Protocols/project-model-v2.md) 和 [包契约](../../Protocols/project-package-v1.md)。包实际包含 project.json、metadata.json、天气 assets 和保留的不透明附件；不把旧目标目录布局描述为当前实现。

继续复用完整输入、来源和快照。P0 SimulationRequest 目前仅有 identity/fidelity，RunReceipt 没有数值结果；不能直接承载本地方法。本页命名均为N1待实现的设计，未发布schema。详细字段、canonical字节约定、事件/缓存/包预算以[AI执行规范](10-ai-execution-guide.md)为准，实施时在独立协议中最终冻结。

## 本地分析契约

| 值类型（拟定） | 内容与不变量 |
|---|---|
| AnalysisMethod | kind、版本、结果等级；首期 airflowPreview、powerEstimate、steadyHeatBalance |
| AnalysisReadiness | 按方法列出阻断/警告、字段路径、实体身份、支持范围 |
| AnalysisConfigurationStore | storeVersion/projectID、按scenarioID索引的method配置；与项目输入同一撤销事务 |
| ResolvedAnalysisInput | 原始场景快照、显式采用的预设/覆盖、方法配置、数据出处；提交后不可变 |
| LocalAnalysisRequest | requestVersion、RunIdentity、方法、resolved input、资源上限 |
| LocalAnalysisEvent | runID、scenarioID、sequence、stage、进度或终态；AsyncStream 值事件 |
| LocalAnalysisResult | identity、method/version、状态、检查、假设、excludedEntities、缺失原因、路径或聚合指标 |
| SceneDescriptor | domain Z-up 几何与 UUID、显示符号、路径；不含 Entity、UI 类型或热负荷算法 |
| ComparisonSnapshot | 固定基准/候选 run、评价配置 hash、时段/单位/假设一致性、可比较项及解释 |

AnalysisMethod 与旧 l0…l3 enum 并存，禁止把规则预览映射成 l2。检查通过的语义是“本方法输入/算法检查通过”，与物理验证、现场校准等级分开。任务成功、检查、freshness 保持三条轴；原有 QualityState.passed 不能单独表示现实可信。

## 能力检查与未知值

几何查看仅需有效几何；气流规则还需合法风口方向和支持对象。墙体 U、送风温度、COP 或天气缺失不能阻断仅需几何的预览。费用方法必须独立检查功率、时段和费率。

复用已有语义校验的相关项，不关闭校验或用默认值掩盖问题。保留原 inputPreparation 为将来的严格引擎门槛。结构损坏/非法单位/越界仍阻断相关方法；未知几何影响路径时必须阻断或显式限定可分析范围。

用户采用假设时保存假设 ID、版本、取值/区间、单位、来源、覆盖原因；不覆盖项目中的 unknown。缺失结果采用 missing(reason)，不是 0。风档类别不是 VolumeFlow；无量纲 pathStrength 不是 Speed；规则覆盖标签不是 ComfortMetric。

## 哈希、缓存与比较

N1 定义并测试规范化编码：类型tag/长度前缀、稳定UTF-8键序、数组语义顺序、有限Double二进制/-0、未知数字原token；保存方法版本及解析后的实际假设。禁止使用 Swift hashValue 作为持久身份。

分别保存完整证据snapshotHash、方法新鲜度inputHash、计算复用computationHash、费用/比较evaluationHash。计算缓存key覆盖几何、所选场景相关输入、方法/规则版本、预设实际值、路径分辨率/seed，并限定project/scenario/method命名空间；首版不跨方案重绑定实体载荷。相机、颜色、动画播放时间和标签不改变物理/规则 key。功率估算 key 不必因风向改变而失效；必须通过相关字段投影测试证明。

费用评价另有 evaluationHash，包含时段、电价、币种和方法；分享含匿名化配置。复用计算结果时生成当前请求自己的 run 归属，不把基准 runID 贴到候选上。未知扩展、天气/数据文件如参与方法则纳入内容哈希。

## 项目包与持久化

计划以`analysis/configuration.json`保存按方案索引的显式方法配置，以`runs/<run-id>/native-analysis/{input.json,result.json,manifest.json}`保存小型分析证据；路径含于result，不另保存逐帧动画。manifest声明owner/版本/身份/相对名/长度/hash。费用在run下evaluations/<evaluation-hash>.json追加至manifest，input/result不改；固定比较保存为analysis/comparisons/<comparison-id>.json，独立owner/version及bodyHash。相机/选择为独立显示状态，不进入物理模型或分析输入undo。N1-05先实现artifact边界，N5-03验收完整文档事务与保存/重开。

metadata.json v1 当前拒绝未知键，不直接添加 analysis 或 view 字段；新增侧文件或升级包版本都需兼容决策和迁移测试。DocumentGroup 管理的包只通过文档事务保存，不从分析 actor 向同一 URL 写文件。运行结果通过 Sendable 值交接到文档层，预算失败保留原包和编辑输入。

当前包默认上限为 4096 条目、32 层、64 MiB 单文件、256 MiB 全包；P2 以值保存附件，会占用内存。本地路径采用紧凑数组、有限历史，首版不保存逐帧动画或稠密体积场。原生input/result/manifest初始上限为8MiB/2MiB/64KiB，配置Store≤1MiB、费用/比较单项≤256KiB，已识别全部分析侧文件累计32MiB；超过时保留原包并标结果未保存。规模增加后另立流式artifact store，不默认扩大上限。未知/未来记录无损保留；外部侧文件更新与输入/config统一撤销按执行规范处理。

## 跨语言与未来场数据

共享 ProjectDocument 字段变化同步 model spec、Swift Codable、Python、schema、迁移和 contracts；App 专属本地 request/result 使用独立 schema，由 Swift 与独立 schema validator 验证，Backend 不必实现同一算法。消费者安装 App 不需要 Python，研发契约检查仍可使用锁定 Python 环境。

N3 不要求二进制场。若 N6 引入原生网格/外部结果，header 必须写坐标、单位、origin、spacing、dimensions、轴序、float32/endian、mask、长度和 hash；真实速度场与规则方向场使用不同 channel/方法。墙和家具内的 invalid 不当作零参与统计。
