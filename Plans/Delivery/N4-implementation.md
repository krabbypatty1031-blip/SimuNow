# N4 实现与交接记录

独立 worktree native-n4，基点40718df27beac4081c5666e0e59566c9487e43e4。全局计划/状态/台账由根代理维护。本次范围为N1～N4，未开展N5比较持久化、报告/PDF或消费者发行。

## 执行规划

1. 复用N1 DTO，补显式覆盖、额定确认、显热账目与范围证据；同步独立native schemas及真实Swift交换。
2. 完成功率窗口完整性、草稿已知小计、积分及真实生产executor，不从制冷量或P2 fraction推用电。
3. 完成Decimal分段费用和固定父run评价；文档只扩manifest索引，保留原input/result字节。
4. 完成explicitAggregateUA显热ledger、来源/排除/容量筛查及至多2输入端点情景。
5. 完成固定纯值比较、背景口径/新鲜度/零分母检查，不给无依据最佳/概率。
6. 接入冻结配置草稿、当前/过期/缺项/保存失败/来源UI与独立真实DEBUG probe。
7. 完成反例测试、contracts/mac/ios、自审，精确提交N4源码和本记录。

## 文件归属

Core/Analysis DTO和独立schema；Simulation/ThermalEstimate算法/费用/比较及生产注册；Workspace/Analysis和Comparison工作流；Documents费用侧文件事务；Apps仅真实client注入与独立DEBUG入口；Tests/Scripts契约验证。本记录由N4代理维护，不提交复制的全局Plans/README/scheme或用户文件。

## 实际接口与输入权威

- Core复用N1的PowerEstimateConfiguration、SteadyHeatBalanceConfiguration及typed payload，兼容增加可选coverage、internalSources、exclusions、额定连续确认、合计设备ID/范围说明、测量时段、SHR与总能力、sensitivity、ledger完整性/范围/情景。没有改ProjectDocument v2或P0字段。
- Core新增CostEvaluationRecord/Configuration/Payload/Segment和Heat相关证据DTO；ComparisonSnapshot复用N1类型，新增可选decisionVariables/metrics。独立cost-evaluation/comparison-snapshot schemas、Core打包资源、生成器与真实Swift→Python校验同步。
- PowerIntegrator.draft返回已知小计及覆盖分钟；integrate只接受完整请求窗口。半开窗口0…1440，跨午夜显式拆段；outside窗口unknown不阻断采用段，结构非法仍全量拒绝。basis为measuredAverage/declaredScenario/ratedContinuous；实测来源和测量时段、额定连续确认必须显式。多设备必须合计覆盖全部ID。P2 fraction只在用户明确采用0/1开关时可转换，.5不作压缩机启停率。
- PowerEstimateExecutor、SteadyHeatBalanceExecutor已注册LocalAnalysisClient.production，App共用原2运行/8排队actor。每次再次计算创建新runID，已有完成结果不能导致重复ID拒绝。
- N4采用配置为冻结权威。P2人员/设备总显热×代表分钟有效比例可通过按钮明确导入清单；总显热只计一次，不另外加对流/辐射/潜热。之后高级条件改动不会自动进入本结果，UI清楚提示需重新导入/采用。power方法hash含实际覆盖device IDs和冻结配置/来源/basis/时段；方向、相机、电价及未采用P2热量不改变power计算。heat只用冻结配置，包含conditionMinute/来源/覆盖/能力/SHR及范围。
- SteadyHeatBalance.calculate生成UAΔT、ρcp新风ΔT、ρcp渗风ΔT、内部总显热、太阳显热五项账目，保留Qsigned，Qcooling=max(0,Qsigned)。ρ、cp和所有bounds一起检查支持范围。unknown阻断或逐项明确排除理由并标declaredSubset；任何子集不通过完整容量筛查。显热能力来自直接显热或有来源总能力×SHR，SHR未知不取1；能力lower/upper与负荷包络保守筛查，重叠不可筛查。
- 每个采用heat范围必须显式纳入sensitivity，至多2个区间、4端点+1名义；已知相关性需分立情景，不能假独立概率。清单每项的bounds首版明确拒绝，需改用一致且有来源的合计范围入口。
- CostEvaluator.evaluate严格绑定固定父power request/result并重核积分，不建立额外假求解run。功率/费率/窗口边界并集分片，单币种Decimal累加；power与tariff非负bounds端点同时传播。缺价格/币种保留missing，父电量仍可用。短round-trip十进制输入进入Foundation Decimal，精确货币数值以JSON字符串保存；仅最终UI按displayFractionDigits作half-even展示。
- 费用采用的功率/费率nominal及bounds仅支持0或1e−12…1e12。该明确数值限制规避本机Foundation Decimal对1e−128乘法返回巨额值而不报错的指数边界；极小非零值拒绝费用评价，电量独立可用。0和真实小额累计保留。没有编造税费、设备报价、订阅/安装费、回收期或全年收益。
- NativeCostEvaluationCodec.make(record,parent,entries)在后台校验父manifest全部已列SHA/大小，封装不可变原Data与索引票据；单评价≤256KiB。appendingCostEvaluation在最新document事务核对身份/原字节/索引及预算，只追加evaluations/<hash>.json和小manifest，input/result字节不变。重复hash同内容复用，冲突/后台后未验证索引变化原子拒绝并保留会话computed fee与failed保存状态，可重新评价；未知未列附件保留。
- NativeArtifactCodec.decode额外核对request.snapshot.projectID==manifest.projectID，并核验列出的评价附件SHA/大小。loadEvaluation进一步严格重算固定父费用语义。
- NativeAnalysisCodec对passed power检验片段顺序、完整覆盖、片段积分与小计/total一致，对heat检验明确完整/子集ledger、排除项、总和/cooling与情景包络；partial passed、重复/倒序片段、未知排除项和nominal超范围被拒绝。
- ThermalEstimateEvidenceValidation.validate按方法version=1调用PowerIntegrator/SteadyHeatBalance纯函数，从冻结配置廉价重算数学证据；检验片段积分、功率范围、显热每项账目/总和/冷负荷、容量筛查、采用范围和端点情景。FixedEstimateEvidence、CostEvaluator及NativeArtifactCodec.make/decode均调用它；自一致伪账目与伪容量、整体同比修改功率片段+total、遗漏输入bounds不能通过。旧N1合法名义记录可省略新增零宽范围/名义情景，不用自报hash代替计算核对。
- EstimateComparator只接收固定纯值request/result/current hash/cost。校验方法/version、参考窗口、采用basis、背景覆盖/conditionMinute、来源与范围、checks/freshness、币种/费率、零分母。变化字段必须显式声明；heat UI默认空决策声明。仅重命名不改变N3几何/目标口径；范围重叠不稳定排序，过期/口径不一致cannotRank。费用币种不同可独立保留有效energy比较。旧ComparisonSnapshot不会实时替换为新证据。N4不保存ComparisonRecord。

## 验收对应与自动化证据

26个N4测试包含解析式、失败反例、真实生产actor/coordinator、文档磁盘关闭重开及固定比较；以下是自动化覆盖，不代表未执行的手动交互已通过。

| 验收 | 自动化/源码证据 | 显示/交互范围 |
| --- | --- | --- |
| V-N4-01/02 | n4PowerAnalyticalSegmentsAndCrossMidnight：2/1.5/10kWh，半开拆段 | 两端源码已接参考窗口/单位；交互待验 |
| V-N4-03 | n4PowerUnknownGapAndExplicitZero、n4PowerRejectsMalformedAndUnsupportedBasisEvidence、n4NativeResultBoundaryRejectsPartialPassedAndWrongLedger | 缺项、小计/覆盖、非法文本不提交；手动待验 |
| V-N4-04/05 | 功率basis确认/.5拒绝、n4PowerAggregateCoverageAndMethodHash、n4ComparedBasisIgnoresUnadoptedAndEquivalentSplitting | 导入只是草稿，来源/实测时段/合计覆盖可查看；手动待验 |
| V-N4-06/07 | n4CostDecimalBoundaryUnionAndMissing、分片并集与0.3 Decimal累计 | 逐片精确值可查看；跨价UI待验 |
| V-N4-08/09 | 缺价/币种/重叠/负价反例、evaluationHash改变、n4CurrencyMismatchKeepsEnergyIndependentlyComparable | 费用missing/过期不使有效电量消失；手动待验 |
| V-N4-10 | n4CostManySmallFragmentsNoDisplayRounding、n4DecimalUnderflowCannotBecomeFreeEnergy：1e−128/1e−100及tiny bounds拒绝、合法0/1e−12保留 | 最终0.24 EUR展示/0.24012精确详情；交互/读屏待验 |
| V-N4-11/12 | n4HeatAnalyticalLedgerAndNegativeSignedBalance：1000/2200W；n4HeatInternalSourcesCountTotalOnceAndRangesValidate | ledger/内部清单实体ID/比例/来源已显示；手动待验 |
| V-N4-13/14/15 | n4HeatExcludedSubsetAndCapacityEvidence、unknownSHR、负Q_signed、容量范围重叠不可筛查；合法显热不需要COP/湿度/MRT | Tin采用、完整/子集/容量限制可读；手动待验 |
| V-N4-16/17 | n4HeatTwoInputsFiveScenariosNoProbabilityAndNoIgnoredRange、n4InternalSourceIntervalsRejectedRatherThanIgnored；2区间640…1440W、相关/超2拒绝、范围重叠 | 端点采用值/来源/局限和所有范围已显示；手动待验 |
| V-N4-18/19 | n4ComparisonFixedFreshnessWindowsZeroAndRanges、未声明功率改变cannotRank、相同功率角度差energy=0、n4OnlyRenamingDoesNotInvalidateQualitativeComparisonBackground | 明确决策checkbox、冻结旧证据与过期说明；手动待验 |
| V-N4-20 | n4PublicSourceScenarioAndIndependentWireExport：真实Swift1.2kWh/0.24012 EUR；官方PDF文本核对 | 来源日期/适用范围/单位/限制已接两端；native CUA不可用，不能记交互/VoiceOver通过 |
| 文档/跨阶段边界 | n4CostAppendKeepsParentBytesAndDiskRoundTrip、多评价ticket/未验证并发索引拒绝、n4ForeignProjectManifestCannotRebindRun、n4CostSaveFailureRetainsComputedSessionRecord | 计算成功与保存失败独立，磁盘重开codec有效；历史自动恢复由总审核查 |
| 草稿/调度 | n4DraftRetainsSourcesRejectsNaNAndUsesSameUndo（未编辑完整heat草稿与原config相等）、n4CoordinatorRepeatedCalculationUsesFreshRunIDs、因果nativeConsumerCancellationReleasesJobsAndNoMainActorCPU | 来源/可选nil/排除顺序/隐含字段保留、P2同一undo事务、连续两次run；手动待验 |
| 数学证据边界 | n4ForgedPowerScaleAndOmittedInputBoundsCannotEnterEvidence、n4ForgedHeatLedgerCapacityAndOmittedEndpointsCannotEnterEvidence | 自一致伪账目/伪容量/整体功率同比变造不能进入固定比较或文档；自动化通过 |

最终验证于2026-10-03完成，全部exit 0，原始日志保留在本worktree的忽略目录`Artifacts/N4/`（交接不提交build/log）：

- `SIMUNOW_PYTHON=/Users/pacoramirez/Desktop/SimuNow/Backend/.venv/bin/python Scripts/check.sh contracts`：`Artifacts/N4/final-contracts.log`。191 shared Swift（含26 N4）+2 Extension、39 Python；23真实Swift native记录+17独立拒绝变体+字段断言；v2/P0 2项目/快照+28错误/兼容反例。shared Swift耗时116.550秒。
- `Scripts/check.sh mac`：`Artifacts/N4/final-mac.log`，正常Mac App BUILD SUCCEEDED。
- `Scripts/check.sh ios`：`Artifacts/N4/final-ios.log`，正常iOS Simulator App BUILD SUCCEEDED。
- 独立Debug probe构建使用`xcodebuild`的正常App scheme、`OTHER_SWIFT_FLAGS=$(inherited) -DSIMUNOW_THERMAL_PROBE`、下面独立bundle ID和`/private/tmp/SimuNow-N4-Probe` derivedData；两端`CODE_SIGNING_ALLOWED=NO`。日志`Artifacts/N4/final-probe-mac.log`与`final-probe-ios.log`均BUILD SUCCEEDED。
- 新数学变造反例专项2项：`Artifacts/N4/math-evidence-tests.log`；数学/完整草稿/因果取消边界专项4项：`Artifacts/N4/boundary-causal-tests.log`，均通过。最终源码`git diff --check`通过。

先前全测189项曾在严重系统调度停顿时复现旧consumer cancellation测试的cacheCount==0失败：5秒sleep先于consumer实际启动到时，原测试缺少取消先后的因果保证；不是据此宣布生产取消失效。已改为test-only gate executor，先确认execute与consumer实际启动，执行器仅收到取消才恢复并抛CancellationError，再严格检查实际退出、running/queued清零与cacheCount==0；30秒只作测试挂起保护，未弱化断言/跳过/串行化。此修复专项和本次191项全测均通过。构建/自动化逻辑验证不等于真实UI交互或物理精度验证。

## 独立QA入口（不覆盖用户应用）

- Mac：`/private/tmp/SimuNow-N4-Probe/macOS/Build/Products/Debug/SimuNow.app`；bundle `com.simunow.nativevalidation.n4.mac`。
- iOS：`/private/tmp/SimuNow-N4-Probe/iOS/Build/Products/Debug-iphonesimulator/SimuNow.app`；bundle `com.simunow.nativevalidation.n4.ios`。
- DEBUG `SIMUNOW_THERMAL_PROBE`只准备输入，使用真正WorkspaceDocumentView和App共享production client，没有预制结果。正常App入口已接同一N4面板。
- 打开“工作区”顶部“电量、电费与显热情景”Disclosure；分别点击两卡“计算当前情景”。公开来源情景应得08–10点1.2kWh、合成热1000W；父power已加入项目后点“评价当前电价”，显示0.24 EUR，固定详情0.24012 EUR。展开采用输入/来源及费用片段。
- 顶部“输入反例”切换：有来源范围（power400…800W→0.8…1.6kWh、heat640…1440W，4端点+名义）；功率/太阳未知（阻断与小计）；明确排除太阳子集（heat可算，容量不可筛查）；总能力已知SHR未知（heat可算，容量不可筛查）；只有制冷量无电功率（power不可计算）；附件路径冲突保存失败（真实runs文件冲突，结果保留会话并标未保存）。
- “功率与时段”改变功率/来源/basis/窗口并采用，旧结果过期；非法NaN/中间文本不能沿用旧值提交。“参考日电价”改变rate/currency后原power仍可用，原fee过期；重新评价追加新固定记录。
- 显热编辑提供所有单位/来源/明确排除、Tin确认、UA/内部覆盖、空气适用条件、能力/SHR和区间关系；导入人员/设备后高级条件改变须重新导入/采用。
- 在“方案”逐一切换各方案、工作区计算并加入项目，再用“固定情景估算比较”选两方及明确决策checkbox并冻结。三个方向相同功率不会得节电差；heat不自动把所有背景差当决策变量。之后编辑只标旧固定比较需重新冻结，不替换其证据。
- “导出项目包/重新打开项目包”使用生产文件IO。磁盘codec已自动化测试，实际系统保存面板/最近重开/自动历史恢复仍需总审分别验证。

## 来源核对

[Mitsubishi Electric官方February 2026厂家PDF](https://library.mitsubishielectric.co.uk/pdf/download_full/4788) p2 MUZ-AY25VG2 SYSTEM POWER INPUT 制冷nominal0.60kW；2.5kW制冷量为不同物理量。[EDF官方Tarif Bleu价格PDF](https://particulier.edf.fr/content/dam/2-Actifs/Documents/Offres/Grille_prix_Tarif_Bleu.pdf) p1自2026-08-01法国住宅Option Base 6kVA为20.01 euro cents TTC/kWh。明示合成参考08–10点连续额定情景→1.2kWh/0.24012EUR，不是实测或实际账单；订阅/设备/安装不含，已含税不另猜税。官方PDF浏览文本独立核对，截图接口未返回像素且下载曾不完整，未声称完成PDF视觉核对。

## 自审、限制与根总审交接

已修正审查发现的采用窗口outside unknown误阻断、容量区间名义误保证、heat未展开区间假零宽、内部清单区间被忽略、费率范围漏传播、比较basis片段划分误阻断、未声明背景差自动放行、纯重命名误阻断、草稿来源丢失、重复runID、费用未最终格式化、passed partial/wrongledger、跨项目manifest重绑定、极小Decimal巨额值和新增费用MainActor SHA成本、自一致伪热账目/伪容量/同比变造功率通过哈希边界、原取消测试缺少因果保证。没有unchecked Sendable或关闭Swift6检查；没有新依赖安装/外部数值引擎/生产隐藏热常数。

待总审处理的已实现跨阶段风险：AnalysisEventCursor/AnalysisCoordinator现有完成事件大载荷同步validateEvent；detached普通run artifact未保存取消并在await后只复核projectID；同projectID外部文档替换需文档实例/revision隔离；历史当前恢复/Workspace同步全project integrityReport的成本。N4复用这些现有组件，未把错误视作可推迟的新功能；根代理本次N1～N4总审正负责修复与回归，并将数学evidence matcher接到Client完成/缓存前及Coordinator后台接受完成事件前；N4提交未宣称这些尚在整合的跨阶段修复已完成。新增费用/比较worker都有取消传播、generation/冻结输入复核，费用票据只允许已验证父字节。

运行限制：native CUA getApp实际超时约977秒并返回−10005，根明确不再重试，不使用AppleScript/CGEvent等绕过；Mac/iOS真实编辑、动态字体/深浅色、VoiceOver与GPU帧耗时未验。macOS14/iOS17最低运行时当前不可用，当前SDK两端编译不能代替最低系统实机运行。现有N3满预算Release client约520ms、典型75ms不含准备/封装；N4全测里的Debug CPU数字受并行/系统阻塞影响，不冒充GPU性能或无bug。完整范围与来源是声明情景的透明账目，没有现实预测精度/CFD/PMV/动态降温保证。
