# N5：日常使用流程与离线交付

版本：详细执行稿v1，2026-10-03。状态：本轮已获得 N5/N6 实施授权，代码已实现；Apple 平台、PDF 实际页面与安装验收待运行时。前置N1/N2/N3核心功能。目标为可保存、可解释、可比较的离线闭环。

当前实现/检查与未验收项见 [N5/N6交接](../Delivery/N5-N6-implementation.md)。下面已勾选项表示代码实现；涉及实际平台、试用与发行的步骤仍保留未完成，不能据此宣称发布就绪。

## 阶段目标与范围

用户能从房间/设备/关注点进入规则预览，调整方向，保留基准并比较两个候选，查看证据，保存关闭重开并分享文字建议。工程高级表单保留，但不能成为只看风向的必填门槛。

先读[AI执行规范](../References/10-ai-execution-guide.md)、[验收案例](../References/11-native-acceptance-cases.md)、[平台计划](../Delivery/platform-and-release.md)。本阶段任务分清单测、实际平台操作、试用与发布候选；正式上传、商店提交或对外发布依后续用户明确授权执行。

## 现有代码接入点

| 已有文件 | 需要保留的行为 |
|---|---|
| [WorkspaceView.swift](../../Packages/SimuKit/Sources/SimuWorkspace/WorkspaceView.swift) | 工作区导航与平台布局；不要另建独立项目状态 |
| [WorkspaceStore.swift](../../Packages/SimuKit/Sources/SimuWorkspace/WorkspaceStore.swift) | 原子编辑、基准、undo；异步结果不得触发load清空undo |
| [ProjectTemplates.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Templates/ProjectTemplates.swift) | 模板值与假设来源；选择模板会改输入，须可撤销 |
| [RoomObjectsView.swift](../../Packages/SimuKit/Sources/SimuWorkspace/ObjectEditor/RoomObjectsView.swift) | 对象列表、字段编辑/选择；为二维和读屏保留完整入口 |
| [ScenarioEditing.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Scenarios/ScenarioEditing.swift) | 候选复制/基准；几何由方案共享，嵌套实体ID可跨方案重复 |
| [WorkspaceDocumentView.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Documents/WorkspaceDocumentView.swift) | DocumentGroup binding权威、导入草稿与iOS导出/再开流程 |
| [SimuNowDocument.swift](../../Packages/SimuKit/Sources/SimuWorkspace/Documents/SimuNowDocument.swift) | 整包预算、unknown附件、天气哈希；不增加第二磁盘写入者 |
| [ReportContract.swift](../../Packages/SimuKit/Sources/SimuReporting/ReportContract.swift) | 旧ReportRequest只有projectID/runIDs；不能当作完整本地证据报告 |

## 任务顺序与归属

| ID | 前置 | 首要交付 | 优先级/归属 |
|---|---|---|---|
| N5-01 | N1就绪度、N2、N3协调器 | 常用设置、家庭模板、统一输入事务 | Must / Workspace |
| N5-02 | N5-01、N3关注点结果 | 条件建议、基准与两个候选 | Must / Simulation/DecisionRules；Workspace/Comparison |
| N5-03 | N1 artifact接口、N3真实结果 | 文档侧文件、重开与跨端导入导出 | Must / Documents/Analysis |
| N5-04 | N5-02/03 | 固定证据文字/JSON/PDF分享 | 本次全部交付 / Reporting/平台入口 |
| N5-05 | 01…04及N2旧系统分支 | 离线、可访问性、文档实际QA | Must / Tests/Delivery |
| N5-06 | N5-05核心操作门槛 | 资源/许可/隐私/签名配置、安装候选和彩排 | Must / Apps/Configurations/生成器 |

可先做03纯artifact事务，再做01/02界面。共享WorkspaceStore、Core契约、Document绑定由一个整合人修改；Reporting不引入Visualization计算依赖。

## N5-01：把常用操作前置，统一撤销

**输入**：当前project/所选方案、AnalysisReadiness、AnalysisConfiguration和N2选择。**输出**：真实可操作的日常面板；明确配置假设与编辑状态；保留高级入口。

**位置**：Workspace/Analysis/DailySettingsView.swift、AnalysisConfigurationDraft.swift；Workspace/Templates；WorkspaceView/WorkspaceStore必要集成；DesignSystem只增加通用状态/单位样式。

执行步骤：

- [x] 首屏依次提供房间尺寸、设备/等效风口、风向、关注点、预览及比较入口；只列当前能力必需缺项。U/COP/天气/湿度放高级条件，不屏蔽原表单或修复报告。
- [x] 常用状态、功率basis、比较排序/缺项与字段名称使用面向用户的中文及对应本地化资源；accepted/ratedContinuous/conductance等内部枚举或字段键放证据详情，不能成为唯一提示。数字按界面区域格式化，单位始终显示，固定证据保留原SI/Decimal值。
- [x] 复用P2房间/对象草稿与完整事务。yaw按现有AirflowDirection的+X→+Y定义，pitch水平→+Z；提交时用同一unit转换，不以显示角度直接替代direction向量。
- [x] 明确展示并确认N3展示档案及参数来源；“预览密度”低/中/高只改16/32/64路径数。设备模型没有风档字段时，不把密度保存成实际空调风档或风量。
- [x] 常用面板中的设定温度与送风温度名称/单位分开；没有实测/来源不推断送风温度。未实现自动控制、真实风档映射、扫描不出现可点击空按钮。
- [x] 空白、办公室、教室继续可用；增加家庭房间模板时使用现有SpaceType.home，不添加未经契约迁移的bedroom/livingRoom枚举。床/沙发可为盒体几何，中性名称；材料/热源保持未知，模板全部假设可查看。
- [x] analysis配置改变与项目输入改变采用统一输入检查点；扩展已有undo或统一协调器，记录project/metadata/configuration的完整前后值。不能让两个撤销栈不同步；晚到结果、相机/选择不进入输入undo。
- [x] 一个输入事务成功后递增revision、失效相应结果、发出一次防抖请求；undo/redo恢复配置与方向后重新评就绪度，不能只恢复UI草稿。
- [ ] Mac保持工作区+inspector；iPad自适应分栏；iPhone能经导航访问对象/条件/比较。缺输入提供实际字段修复动作，保留unknown，不强制填写所有高级项。

**验证**：V-N5-06/07、V-N3-14…16；test与双端编译。**完成门槛**：从空白/家庭模板到预览没有热工必填项；配置与项目undo一致；选择、错误修复和高级条件始终可达。

## N5-02：有依据的建议与候选比较

**输入**：检查通过的固定N3结果、当前freshness、基准/候选身份；若有N4则接其固定评价。**输出**：RecommendationEvidence、SuggestionCard和ComparisonSnapshot，全部条件可查看。

**位置**：Simulation/DecisionRules/PreviewRecommendationRules.swift；Workspace/Comparison/ScenarioComparisonCoordinator.swift、ScenarioComparisonView.swift、SuggestionCard.swift；Core沿N1证据DTO。

执行步骤：

- [x] 先写纯建议规则，首版使用N3 RuleID：路径相交→提示可尝试移开关注点方向并再比较；遮挡→提示查看遮挡家具及未模拟区域；notEvaluated→指出具体缺项。outside不能宣称无风/舒适通过。
- [x] 每卡保存RuleID/version、runID/scenarioID/inputHash、关注点/家具ID、使用档案及条件。卡片用“在当前假设路径下…”等条件表达，多个样点保留各自关系，不压成舒适分。
- [x] stale/failed/unsupported结果不能生成当前有效建议；历史卡允许查看并明确过期。缺有效样点时只给补充输入动作，不生成排名。
- [x] 复用P2复制建立基准+两个候选；保留独立方案UUID。复制分析配置到新scenario key并保留假设来源，清除当前run绑定；不能借用旧方案runID/实体结果载荷。用户固定比较时生成comparisonID，以ComparisonRecord（owner/version、固定snapshot、bodyHash）经03文档事务保存；具体schema和Swift输出校验在本任务补齐，不自动保存每一帧临时比较。
- [x] 显式说明房间/家具geometry共享；移动家具影响全部方案并使相关run过期。若要比较不同布局，首版另存项目，不能暗示现有候选已经隔离geometry。
- [x] 比较先通过同方法/version/档案/背景输入的口径检查；决策变量如风向单列。同视角采用可序列化相机值同步到两个viewer，不能共享Entity/全局选择或拖动另一窗口。
- [x] 对应关注点按scenarioID+entityID匹配，分别列相交/遮挡/范围外/不可评价；缺一侧不能写改善。若有N4，电量/费用采用其比较检查；仅改角度不生成节电百分比。
- [x] “编辑风向/家具”动作只打开有功能的现有表单；没有计算出的可执行数值，不提供一键最优。所有已授权编辑仍走草稿验证/undo，而不是建议引擎直接改项目。

**验证**：V-N5-08…10；V-N4-16…19仅在N4实现后执行。**完成门槛**：一个基准两个候选可重复比较；每个结论有run与实体证据；缺失/过期不能伪装最佳或舒适结论。

## N5-03：分析侧文件、原子合并与重开

**输入**：N1 artifact codec、最新SimuNowDocument值、配置和不可变run证据。**输出**：可保存/关闭/重开的原生包及准确persistenceState；iOS实际导出再开证据。

**位置**：Documents/NativeAnalysisEntries.swift、AnalysisDocumentTransaction.swift；SimuNowDocument增加值事务方法；WorkspaceDocumentView增加配置/附件变化通道；Workspace/Analysis/AnalysisHistoryStore.swift。不增加独立URL写入服务。

执行步骤：

- [x] 冻结`analysis/configuration.json`容器：storeVersion/projectID及按scenarioID索引的method配置；配置假设与实体归属一并存。只保存显式输入，不把相机和当前选择当物理输入。
- [x] run路径统一为`runs/<run-id>/native-analysis/{input.json,result.json,manifest.json}`。manifest列owner、版本、run/project/scenario、相对名、长度/SHA-256；result需与request身份/method/hash一致。N4费用评价以evaluations/<evaluation-hash>.json追加并列入manifest，原input/result不可变；固定比较以analysis/comparisons/<comparison-id>.json保存，校验bodyHash及run/input/evaluation引用。
- [x] 校验路径/重复ID/完整文件/哈希/单位/版本，使用N1预算：input≤8MiB、result≤2MiB、manifest≤64KiB，配置Store≤1MiB，单费用/比较≤256KiB，已识别配置/run/费用/比较累计≤32MiB且满足原整包上限。未知/未来附件无损保留，不能解成有效run或删除回收预算。
- [x] 所有新增/更新配置与run先构造完整新文档值，成功才替换binding；任一验证/预算失败保留原包和输入，结果可留会话但标“未保存”，不声称历史已落盘。
- [x] 为SimuNowDocument定义会话内稳定documentInstanceID：普通值事务和侧文件追加保留它，重新读文件/替换文档创建新ID；它不写入公共物理JSON。异步请求捕获instanceID/projectID及任务generation，完成后先检查归属，再合并到最新preservedEntries。仅projectID相等不够，同projectID的新文档也不能接收上一实例的晚到结果。
- [x] 区分输入revision与侧文件revision：同实例输入已更新的旧run可进入其历史，但不能覆盖当前新hash；侧文件变更期间的新天气/unknown附件必须按最新binding保留。方案已删除不复活，以orphaned历史处理。后台历史解析另捕获侧文件revision，返回时若已变化则丢弃并按最新内容重载；不要用revision相等要求阻断同实例合法历史追加。
- [x] 完成事件的大载荷schema/结果校验放到非MainActor任务，返回后重查identity/sequence/generation；状态接受仍在MainActor按顺序进行。保存artifact构造任务句柄并传播取消，关窗/替换文档取消旧封装与订阅；保持公开codec严格校验、合法旧run历史归属和预算，不能靠删除校验改善响应。
- [x] 外部文档更新要观察配置与已识别run目录的内容变化，不只project/metadata。记录稳定内容摘要/版本并在非主线程解析，避免每次视图刷新全包hash；文档被替换后取消旧订阅并重新协调。Workspace完整性/所选方案报告按真实输入revision缓存；侧文件追加、选择和相机不重复遍历整个项目，输入事务及保存边界仍执行完整验证。
- [x] undo恢复输入/config不删除刚完成的证据；结果持久化不清空输入undo。显式删除历史前检查被比较/分享快照引用，提示影响；首版不自动删用户记录或未知目录。
- [x] 重开先列已校验历史及固定费用/比较，并有界自动恢复当前所选方案和固定比较所需runs；不要求用户逐份点击才能恢复已保存比较，也不预载全部历史数组。引用缺失的比较标不可用但保留原记录，不用当前输入重算来补旧证据。只有当前method inputHash相同且checks通过的run可显示为当前。完整snapshotHash仍校验其原始证据，不能把旧输入快照改成现项目来“变新”。配置缺失则待确认，不自动接纳旧假设。
- [ ] Mac实际另存/关闭/通用打开/最近重开；iOS从浏览器打开→编辑→系统导出→再打开导出文件。JSON修复会话只声明已导出，必须验证重新进入原生文档，不能把模拟器启动当完成。
- [ ] 保存失败、损坏run、未来分析版本、达到预算、两窗口外部更新分别验收；分析记录出错可隔离且项目继续修复，结构性项目损坏仍按P2规则拒绝。

**验证**：V-N5-01…05、11/12。**完成门槛**：已保存run能追溯原输入与方法；期间新附件/unknown字节不丢；当前与历史明确；Mac/iOS实际操作分别记，未取得运行时保持未验证。

## N5-04：固定证据与系统分享

**输入**：被用户选定且有效的固定runs/ComparisonSnapshot/RecommendationEvidence。**输出**：LocalReportSnapshot、UTF-8文字建议、JSON证据摘要及PDF，经平台系统分享。

**位置**：Core/Analysis/LocalReportSnapshot.swift；Reporting/LocalReportBuilder.swift、LocalReportExporter.swift、ReportRedactor.swift；Workspace分享预览；Apps平台分享适配。必要时仅给Reporting测试新增依赖。

执行步骤：

- [x] 定义独立LocalReportSnapshot，含reportVersion、创建时间、固定runIDs/inputHash/方法版本、关系/指标、假设、缺项、来源、比较口径和checks；不要调用只有projectID/runIDs的旧接口后自行读取实时输入。
- [x] 导出前只检查身份/新鲜度/完整性并冻结，禁止Reporting重算路径、负荷、电费或建议。用户导出历史结果时注明“对应历史输入”，不能提升为当前有效建议。
- [x] 首版实现plainText与JSON evidenceSummary两种有实际内容的导出，系统分享入口两端可达；分享前预览所含信息。比较文字逐项列条件，不输出未经实现的温度/舒适/年度节省。
- [x] 默认摘要不含完整房间几何、个人/项目/座位名称、原始照片、开发者路径；采用稳定的“方案A/关注点1”别名。来源引用仅保留允许分享的公共引用，私有路径/自由文本可删减，并列redactedFields。
- [x] 原run的source inputHash用于追溯，匿名摘要另算exportHash，声明已删减且不能重算完整输入哈希；不得修改原始证据或声称删减后的JSON仍为完整原run。完整项目包仍由P2明确导出入口处理。
- [ ] 实现PDF，使用平台适配/公共绘图API承载同一冻结摘要，并复用文字内容；分页、单位、脚注/版本/缺项均检查。将实际导出PDF渲染成页面图，逐页检查中文、长来源、页边界与证据关联；文本抽取或编译成功不能替代版面验收。三维截图不是报告必需内容。
- [x] 分享取消/输出失败可恢复，生成文件放会话临时目录并清理，不向打开的项目URL旁写文件；分享动作由用户触发，不能自动发送给第三方。

**验证**：V-N5-13/14。**完成门槛**：文本、JSON、PDF结论一致；每结论可指回固定证据；匿名化不损坏源记录；PDF真实页面检查通过；两端实际分享/取消有证据。

## N5-05：离线闭环与平台可访问性QA

**输入**：01…04整合App、验收fixtures、可用Mac/iPhone/iPad与最低系统环境。**输出**：E2E操作记录、缺陷/修复和剩余平台限制；不新建无必要UI测试target。

执行步骤：

- [ ] 执行“空白/办公室模板→三维旋转与选取→确认展示假设→调整方向→家具遮挡→基准+两个候选→同视角比较→看依据→保存关闭重开→分享”的完整脚本；家庭模板重复核心路径。
- [ ] 在受控测试环境模拟无网络，或使用无worker/VM依赖的新安装环境；不为证明离线擅自停止用户服务/VM或改全局网络。确认App注入真实local executor，不触发Process/Docker/Python/download。
- [ ] N4存在时补功率/费率估算；缺功率/价格走不可估算脚本；N4未实现保留不可用入口说明，不成为核心E2E阻断。
- [ ] Mac深浅色、键盘/菜单焦点/undo、VoiceOver；iPhone大字号/读屏/导航、横竖屏；iPad分栏/横竖屏。念出对象名、单位、规则状态与按钮作用，颜色有文字辅助。
- [ ] Reduce Motion暂停展示动画，静态路径与对象列表仍可比较；旧macOS14/iOS17完整二维可完成同一任务，不只显示兼容提示或静态截图。
- [ ] 多窗口不同项目/同项目更新、快速连续编辑/切换方案/关窗分别验证；取消旧订阅，窗口相机/选择独立，旧结果不得覆盖当前。
- [ ] 执行损坏/未来版本/预算满/导出取消/存盘失败修复脚本，确认不丢已有附件或未保存编辑。延续P2尚未完整验证的iOS实际导入导出、通用打开、最低系统与读屏项。
- [ ] 至少两端各一次试用理解检查：使用者能说明“规则路径不是真实风速”，能找到假设与缺项。记录用时和误解，发现问题修改界面/文案后复验，不生成满意率百分比。
- [ ] 保存环境/命令/操作/截图/检查结果到忽略的Artifacts/N5，逐个标pass/fail/notAvailable/notRun；缺运行时不把构建替代操作通过。

**验证**：V-N5-15…18及前述文档操作案例。**完成门槛**：核心离线流程与现代两端实际完成；旧系统、真机、读屏未取得证据的项明确列为限制；未通过的Must操作不标发布就绪。

## N5-06：发布候选、资源与演示彩排

**输入**：已通过核心QA的构建、资源/许可证清单、目标分发方式。**输出**：可安装开发候选及发布检查表；具备相应证书后再产签名候选，不混淆两者。

**位置**：Apps/Resources、Configurations；Scripts/generate_project.py及既有schemes；Delivery/platform-and-release/status/verification。App target资源变化由生成器维护，不能只改pbxproj后丢失。

执行步骤：

- [x] 盘点图标/应用名、常用文本本地化、单位格式与隐私/许可页；实现已有功能的解释，不把N6或旧引擎路线写成已具备。
- [ ] 新资源注册生成器，检查重复引用/缺文件；保留用户既有iOS scheme。包内新增Swift源码不改pbxproj；资源变动做生成漂移与两端构建。
- [x] Sandbox保持开启；非AR查看不需要摄像权限。不新增启动下载、后台服务或网络依赖。隐私说明覆盖本地房间资料、用户发起导出与匿名化摘要。
- [ ] 开发安装候选用现有测试签名策略/可用环境；签名分发检查证书、entitlements、bundle ID、安装与打开文档。证书不可用记录阻断，未签名BUILD SUCCEEDED不当正式可分发包。
- [ ] 清洁环境试装/首次启动/默认文档类型/保存重开/升级已有P2包，检查附件与模板来源；Mac和iOS候选分别记录构建号、OS、安装方式与结果。
- [ ] 彩排固定脚本：办公室、三维/二维、规则路径、遮挡、两个候选、依据、保存重开；N4有输入时再展示透明估算。数据是人工几何/公式案例，明确不是实测CFD。
- [x] 汇总全部Must任务的实际证据、未验证平台/Should限制、已知问题与下一步N6；更新status/verification。正式发布/上传由另一次明确授权执行。

**验证**：V-N5-19/20。**阶段完成清单**：N1/N2/N3/N4/N5形成可运行可保存闭环；本次所有任务包括N4和PDF均实现并审查；可安装候选与签名发行分别有证据；不因UI完整标记物理模型验证完成。缺可用最低系统、真实读屏或正式证书时，具体平台项按notAvailable记录，不将构建成功提升为该操作通过。
