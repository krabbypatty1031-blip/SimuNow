# N4：热量、电费估算与方案比较

版本：详细执行稿v1，2026-10-03。状态：代码已整合，713e06e→c502e81；生产功率/费用/显热与固定情景比较已接入，代理自动化通过；根最终修复的201项共享Swift、完整契约与双端构建通过，平台交互仍缺证据，详见[最终审查](../Delivery/N1-N4-final-review.md)和[阶段交接](../Delivery/N4-implementation.md)。前置N1-01/03/04/05；定性比较复用N3，数值估算不依赖RealityKit。路线图优先级为Should；本次用户要求完成N1…N4全部内容，因此01…05均在本次实施范围，不能以Should为由跳过。

## 阶段目标与输入策略

交付透明的“功率×时段”“分段电费”和限定稳态显热情景，用户可逐项查看采用值与来源。不得从风向、面积、设定温度或额定制冷量自动推出实际用电。输入不足返回missing及补充项，不生成默认完整估算。

先读[AI执行规范](../References/10-ai-execution-guide.md)、[验收案例](../References/11-native-acceptance-cases.md)、[方法规格](../References/07-native-method-spec.md)。下文类型、目录和默认预算是待实现约定；功率值、UA、空气参数没有隐藏默认值。

## 现有代码接入点

| 已有文件 | 应复用/应避免的行为 |
|---|---|
| [DomainModels.swift](../../Packages/SimuKit/Sources/SimuCore/Project/DomainModels.swift) | DailySchedule为分钟/比例；TariffInterval为分钟/费率；已有环境、成本、内部热源输入 |
| [ModelRegistry.swift](../../Packages/SimuKit/Sources/SimuCore/Project/ModelRegistry.swift) | SingleSplit的coolingCapacity、electricalPower、cop是不同量；没有平均功率/启停率自动模型 |
| [PhysicalParameter.swift](../../Packages/SimuKit/Sources/SimuCore/Project/PhysicalParameter.swift) | known/unknown、SI单位、SourceRecord和区间；不能把ThermalPower当ElectricalPower |
| [ScenarioConditionsView.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Conditions/ScenarioConditionsView.swift) | 复用高级条件编辑，新增常用估算草稿不写坏原unknown |
| [ScenarioEditing.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Scenarios/ScenarioEditing.swift) | 复制方案值独立，geometry仍共享；比较须冻结具体run |

## 任务顺序与归属

| ID | 前置 | 首要交付 | 归属 |
|---|---|---|---|
| N4-01 | N1基座 | 功率basis、参考时段、积分结果 | Core/Analysis；Simulation/ThermalEstimate/Power |
| N4-02 | N4-01 | 费率分段与独立费用评价 | Simulation/ThermalEstimate/Cost；Workspace/Analysis |
| N4-03 | N1基座 | 显热清单与能力筛查 | Simulation/ThermalEstimate/HeatBalance |
| N4-04 | N4-01；比较费用/热量时再依赖02/03 | 显式情景范围与固定比较 | Simulation/ThermalEstimate；Workspace/Comparison |
| N4-05 | 本阶段已实现的方法 | 解析/反例、来源案例和双端显示审视 | Tests；Delivery |

已有N1公开接口为`PowerEstimateConfiguration`、`AnalysisPowerInterval`、`SteadyHeatBalanceConfiguration`、`PowerEstimatePayload`和`SteadyHeatBalancePayload`；basis实际case为`measuredAverage`、`declaredScenario`、`ratedContinuous`。上述建议文件名不要求再造平行DTO；需要扩展时沿N1独立native schema/codec和真实Swift交换入口同步实现。Core单位/结果schema沿N1契约扩展，先整合再改调用方。N4-03不应迫使01/02接入围护模型；报告只接收已算出的结果。

本次实施采用冻结配置：P2设备电功率、人员/设备显热、有效比例及费用输入可导入为草稿，用户采用后保存明确的AnalysisConfiguration。计算不在后台隐式重读实时高级表单；界面必须列出冻结代表分钟、各内部源及来源，并提示高级输入改变后需重新导入/采用。method投影须包含实际采用配置及被覆盖设备身份；不能把未采用的实时字段写入计算结果。

## N4-01：明确功率口径与时段积分

**输入**：AnalysisConfiguration中的PowerEstimateConfig，含requestedWindows、powerIntervals、timeBasis与来源。**输出**：PowerEstimatePayload，含各片段W/秒/kWh、完整性、累计电量或missing；注册真实power executor。

**位置**：Core/Analysis/PowerEstimateModels.swift；Simulation/ThermalEstimate/Power/PowerInputResolver.swift、PowerIntegrator.swift；Workspace/Analysis/PowerEstimateDraft.swift、PowerEstimateView.swift；相关schema与契约夹具。

执行步骤：

- [ ] 定义功率basis：measuredAverage（实测时段平均）、declaredScenario（用户指定功率/范围）、ratedContinuous（额定输入功率连续运行情景）。实测记录测量时段/来源；额定情景必须显式确认，不标为实际平均功率。
- [ ] 从SingleSplit.electricalPower导入只是草稿建议值，保留来源并要求选择basis；coolingCapacity/cop不参与本方法。不同设备只有明确声明aggregatePower覆盖清单时可作为合计功率，不能默默只算一台。
- [ ] 首版固定`timeBasis=fixed24HourReference`：一天0…1440参考分钟，区间[start,end)，秒数为分钟差×60。它不是带夏令时的实际日期账单。跨午夜22:00→08:00拆为[1320,1440)与[0,480)，保存两段和共同来源。
- [ ] requestedWindows默认整参考日，可显式选择若干不重叠窗口。功率区间必须完整覆盖请求窗口；未覆盖、unknown或中间空缺使方法readiness不就绪/完整电量missing。缺项、实测时段和额定连续确认按与请求窗口实际相交的片段判断；未采用片段的unknown不阻断本次估算，但全部片段的结构、单位和数值边界仍校验。可在输入草稿列“已知时段小计”，明确覆盖分钟；该小计不能保存为checks通过的完整power run或用于有效收益比较。
- [ ] 停机必须为显式known(0 W)记录，不能把未填写时段当停机。拒绝负功率、非有限值、倒序、重叠、越界和范围lower>upper；相邻同源等值区间可合并，但保持证据片段可追溯。
- [ ] P2 DailySchedule的fraction不自动解释为压缩机启停率。仅明确采用0/1开关转换时可生成对应已知功率/零区间；存在0<fraction<1则提示需要功率情景，不能直接乘额定功率。
- [ ] 以`E_kWh=Σ(P_W×duration_seconds)/3_600_000`积分，分别累计名义/已声明上下界；保持Double计算精度，显示时再格式化，避免逐片舍入误差。
- [ ] method输入投影只含功率basis、时段、实际来源/假设和版本。修改风向/相机不改变本方法inputHash；输入修改重算，费用修改只重评费用。

**验证**：V-N4-01…05。**完成门槛**：1000 W×2 h=2 kWh；分段/跨午夜结果可逐段复核；缺项不是零；完整与小计在DTO及UI均可区分；没有“只改风向节电”结论。

## N4-02：分段费用与缺失费率

**输入**：固定PowerEstimatePayload、CostEvaluationConfig（requestedWindows、tariffs、currency、来源）。**输出**：CostEvaluation，含evaluationHash、费用片段/总额或missing，与原power run关联。

**位置**：Core/Analysis/CostEvaluationModels.swift；Simulation/ThermalEstimate/Cost/CostEvaluator.swift；Workspace/Analysis/TariffDraft.swift、EstimateSummaryView.swift。费用不是一个新的假求解run，保留被评价runID/inputHash。

执行步骤：

- [ ] 读取已有CostInputs作为草稿，显式选择参考日电价与币种；费率必须有单位“币种/kWh”及来源。首版单币种，不自动换汇，不补设备报价、税费或回收期。
- [ ] 费用窗口与电量窗口保持同一fixed24HourReference口径；只有完整功率覆盖且费率完整覆盖的窗口才给总费用。未知币种/费率/某段价格返回missing，电量仍可用。
- [ ] 取功率、费率、窗口所有边界的排序并集，逐个半开区间查唯一功率与唯一费率；拒绝重叠，边界相接不重复计费，空隙不延用上一价格。
- [ ] 按每片电量×费率累计。货币使用Decimal或明确等价的十进制策略；N1 schema须记录与既有Double输入的转换/精度规则。仅最终显示按币种配置格式化，不逐片先保留两位再求和。采用功率或费率区间时，非负范围按各片下界乘下界、上界乘上界累计；若某种范围尚不支持，明确拒绝而不是忽略后生成零宽包络。
- [ ] 费率非有限/负值按现有项目语义和首版支持范围明确拒绝，不静默归零；若未来支持负电价另升评价版本。无货币最小单位资料时展示配置精度，不声称已按账单规则结算。
- [ ] 费率/币种变更使evaluationHash变化，不改power inputHash/computationHash；把CostEvaluationRecord（owner/version、父run/inputHash、evaluationHash、采用费率/币种、payload）存为run下evaluations/<evaluation-hash>.json，≤256KiB。appendEvaluation文档事务预检最新父run与预算，只扩充manifest文件索引，原input/result不改；重复hash同内容复用、不同内容报冲突。独立schema与真实Swift输出校验；报告使用固定费用值。
- [ ] UI同时列功率basis、覆盖时段、费率来源、未包含费用项与“情景估算”；缺电价显示待补充，不显示0元/全年节约。

**验证**：V-N4-06…10。**完成门槛**：跨价段逐片可复算；电量与费用独立缺失；货币累加/边界测试通过；未引入年度外推、设备成本或投资回收推断。

## N4-03：限定稳态显热清单

**输入**：SteadyHeatBalanceConfig，首版采用explicitAggregateUA模式。**输出**：HeatBalancePayload，带符号热收支、正制冷显负荷、各项账目、完整性和可选能力筛查；没有温度空间场。

**位置**：Core/Analysis/HeatBalanceModels.swift（分析专用UA单位W/K等）；Simulation/ThermalEstimate/HeatBalance/HeatBalanceResolver.swift、SteadyHeatBalance.swift；Workspace/Analysis/HeatBalanceDraft.swift。不为本方法修改生成的ProjectDocument字段。

执行步骤：

- [ ] 明确代表工况：Tin是用户采用的室内目标/情景温度，Tout是有来源室外温度；conditionMinute为0…1439参考分钟。若复用控制设定点作为Tin，必须用户确认“采用为估算条件”，不当作已达到室温。
- [ ] UA首版只接显式合计值≥0 W/K及覆盖范围/来源。P2表面U值不能按房间面积随意合成UA；逐表面面积/开口/邻接推导延期，除非另补完整契约和独立验证。
- [ ] 室外新风与渗风分别以已知m³/s输入后求和；循环送回风排除。ρ、cp必须有数值、单位、来源和适用条件；不从本计划测试用常数自动生成生产默认值。
- [ ] 内部项列人/设备的sensible总量、采用conditionMinute的有效比例/来源；同一个源按总显热计一次，不能再同时加radiant、convective和total。潜热不是显热。太阳项单列W与来源。
- [ ] 每一必需项允许显式零，unknown不能补零。用户明确排除某项时记录excludedTerm及理由，结果为“指定项子集情景”，不能命名完整房间负荷；被排除重要项时禁止容量合格结论。
- [ ] 计算`Q_signed=UA×ΔT+ρ×cp×(Voutdoor+Vinfiltration)×ΔT+QinternalSensible+Qsolar`；`Q_coolingSensible=max(0,Q_signed)`。保留每项带符号贡献和单位，负收支也不删除。
- [ ] 容量筛查只在清单完整且显热能力有依据时做：直接sensibleCapacity，或有来源/工况一致的totalCapacity×SHR。SingleSplit仅总制冷量不够；SHR未知显示不可筛查，不自行取1。
- [ ] capacityKnown≥required只解释“该代表工况下显热容量账面覆盖”，不生成全制冷选型/舒适通过。能力有范围时，以能力下界覆盖需求上界才可判账面覆盖，以能力上界小于需求下界才可判不足，重叠则不可稳定筛查；totalCapacity×SHR同样传播非负端点。缺COP不影响显热算法，但不能从负荷自动换算耗电；无动态热容量不输出开机降温时间。
- [ ] 作为steadyHeatBalance独立executor注册，保存ledger与输入哈希；无湿度/MRT不伪造PMV、座位温度或湿负荷。
- [ ] 输出详情可逐项查看冻结内部源的entityID、总显热、有效比例与来源；能力及SHR来源、各端点情景采用值同样可达。首版未支持清单内各源区间传播时明确拒绝/要求显式合计范围，不静默忽略已有bounds。

**验证**：V-N4-11…15。**完成门槛**：UA=100 W/K、ΔT=10 K且其余项显式零得1000 W；显/潜、电/热、循环/新风分离；有遗漏的子集不得通过完整容量筛查。

## N4-04：范围、情景与固定方案比较

**输入**：固定基准/候选run、方法专用评价口径和有来源的UncertaintyBounds/显式情景。**输出**：ComparisonSnapshot及确定性范围/不可比较理由；与N5建议卡使用相同run身份。

**位置**：Simulation/ThermalEstimate/SensitivityScenarios.swift、EstimateComparator.swift；Core/Analysis/ComparisonModels.swift；Workspace/Comparison/EstimateComparisonView.swift。

执行步骤：

- [ ] 先写比较条件检查：方法/version、timeBasis、请求时段、币种、代表工况/清单口径、规则档案、有效状态与freshness；候选明确改变的决策变量单列，背景条件差异则禁止“改善”百分比。
- [ ] 风向候选只比较N3路径关系；功率/费用完全相同时展示相同估算，不添加经验节电系数。不同能力结果并列，不揉成无来源综合评分。
- [ ] 首版最多选2个区间输入，生成各端点组合至多4个情景，加1个名义情景；更多输入提示缩小范围。采用的热负荷输入带bounds时，必须全部明确列入sensitivity，漏选或无关系配置阻断范围结果，不能用名义值重复填min/max冒充展开。已知相关性不能当成相互独立组合，缺关系依据显示“端点情景包络”与局限。
- [ ] 对线性单调的功率积分可直接上下界求值；其他方法逐情景运行同一纯函数并保留情景ID/采用值/来源。检查bounds覆盖nominal、单位一致、有限、不违反输入规则。
- [ ] 展示min/max、名义值和各情景条件，不写置信区间或概率。范围重叠/排序随情景翻转时明确无法稳定排序，不标最佳或保证收益。
- [ ] 相同口径且完整结果才显示绝对差；百分比的分母必须为有效非零基准，零基准返回不可定义。不同方法/版本/币种、缺项或过期run不比较收益。
- [ ] 固定comparisonID/comparisonContextHash及被引用runs/evaluation hashes，由N5-02/03将ComparisonRecord保存至analysis/comparisons；N4只产纯值、不直接写包。刷新输入后原比较进入历史/过期提示。N5复制候选后须各自产生自己的run，不借用另一方案的实体载荷。

**验证**：V-N4-16…19。**完成门槛**：比较可复现、有口径检查；区间与概率分开；没有假最优、零分母或状态混淆。

## N4-05：来源案例、反例与双端显示审视

**输入**：已实现方法、验收表、可取得的真实功率/费率来源。**输出**：解析测试、匿名来源记录、双端卡片证据与本阶段可用范围。

执行步骤：

- [ ] 自动验证V-N4-01…19；解析fixtures在Tests/Fixtures标注synthetic，只证明实现符合公式，不冒充现场数据。
- [ ] 至少准备一组可追溯功率/费率输入，记录采样范围、来源日期、币种、实际采用时段。没有真实来源时保持来源案例未验证，解析算法仍可交付，但不得声称账单精度。
- [ ] 用“仅额定功率”“只有制冷量”“未知SHR”“UA已知但太阳未知”“循环风很大”等反例检查UI能否辨认不可估算/子集/不可选型。
- [ ] 在Mac与iPhone/iPad实际检查已知/范围/缺失/过期/保存失败卡片，读屏念出单位与来源，长文本和动态字号不截掉假设。
- [ ] 记录耗时/规模与版本，运行本阶段改动所需test/contracts/mac/ios；来源/用户理解和实际平台项单独记录V-N4-20，不能用83项旧测试替代。
- [ ] 自审所有输出标题：能否被误读为实际用电、已实现室温、完整冷负荷或年度收益；发现混淆修正模型与文案，再更新Delivery证据。

**阶段完成清单**：各已交付方法有独立契约和checks；未交付方法明确不可用；N4仍为Should。RC、湿负荷、PMV、CO2、年度能耗与优化器留给N6/独立扩展。
