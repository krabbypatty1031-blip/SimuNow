# 架构决策记录

当前主线自2026-10-03改为Swift本地分析 + RealityKit，见ADR-014…017。ADR-003/004的外部worker/多保真度主线，以及ADR-010的“唯一主路线”，在首版优先级上已被ADR-014替代；原协议、配置、事实和未来专业复核选择仍保留。ADR-001的Mac优先/共享包及ADR-002最低系统继续有效，移动端新增本地分析由ADR-014扩展。

## ADR-001：双原生 target + 本地共享包（已接受）

背景：Mac 主工作区，iOS 后续采集与浏览；平台能力不同。
选择：两个入口、一份 SimuKit，业务/契约共享，执行与采集适配。
影响：平台编译可独立验证，避免 Process 泄漏移动端；维护两个最小入口。

## ADR-002：macOS14 / iOS17 + Swift6（已接受）

选择：基础 SwiftUI 导航与 Observation 兼容上述系统，并发检查完整。
影响：RealityView 等调用在实现时 availability 或改 renderer；提高系统版本同步 xcconfig、Package 与计划。

## ADR-003：外部 worker 与文件协议（已接受）

选择：不可变 run、JSON/JSONL、二进制场、Python 引擎 adapter。
影响：可复算、可缓存、可远程扩展；Mac sandbox/运行时打包需 P3 实证。

## ADR-004：稳定工况多保真度（已接受）

选择：比赛先 L0/L1/L2；单向边界；代理/瞬态后续。
影响：用户收到代表日与稳态位置评价；年度/降温时间需要另建数据和模型。

## ADR-005：占位明确不可用（已接受）

选择：空工作区、UnconfiguredSimulationClient 抛错、worker doctor 返回 not_configured。
影响：架构可开发，任何显示收益都要真实计算依据；人工 fixture 仅用于接口测试。

## ADR-006：组合与注册扩展（2026-10-02，已接受）

触发：P2-01 必须支持新增设备/几何而不修改项目聚合与中央类型分派。备选：中央 enum/大型设备基类、运行时插件、代码扩展注册。选择：强类型 payload + 稳定 kind/version 外壳，不可变、注入的分类注册表，纯校验规则集合。几何实现自身查询；不引入运行时动态插件或引擎依赖。影响：新增实现/schema 片段/注册项即可接入，新增必需语义仍需版本迁移。证据：独立 SimuExtensionTests 设备全流程与几何查询测试、Python 对应测试。

## ADR-007：未知扩展无损保留（2026-10-02，已接受）

触发：旧 App 打开新设备项目不能丢失数据或伪装可计算。备选：拒绝整份项目、忽略未知字段、保留扩展并阻断计算。选择：JSONValue/FrozenJSON 保存数值 token 与 JSON 结构；ProjectCodec 是唯一项目 wire I/O 边界。未知 kind/version 保留，已知非法 payload 和未来根版本拒绝。影响：字段编辑仅用于已注册类型，不承诺 JSON 空白/键序保留。证据：大整数/高精度、小版本未知、非法已知 payload 和跨语言往返检查。

## ADR-008：项目与不可变场景输入分离（2026-10-02，已接受）

触发：避免编辑覆盖运行输入，并给 P3 留出环境/求解设置和哈希边界。选择：共享几何 + 完整场景值；纯快照保留 project/scenario 身份，将物理输入与成本评价分开。快照尚不等于 RunInput。Swift 使用 let/值语义，Python 使用 frozen/tuple/不可变 JSON。影响：编辑采用新值，P3 加入真实运行身份和哈希；保存留 P2-04。证据：嵌套快照不随项目修改的测试。

## ADR-009：共享结构清单与生成契约（2026-10-02，已接受）

触发：两语言新增完整字段容易漂移。选择：model spec 生成 Python/Swift 结构声明，Python wire model + 注册 schema 生成 Draft2020-12；行为在两语言独立实现并通过真实双向交换验证。Core 打包同一 schema 的资源副本；check 模式拒绝漂移。影响：生成文件不可手工修改，Schema 是结构验证，语义/物理规则另行检查。Swift 的 schema 校验只支持生成器使用的子集，未知断言失败。证据：contracts 的生成漂移、独立 jsonschema 与两端校验一致性检查。

## DESIGN-001：英文建筑浅色 Pitch Deck（已接受）

日期：2026-10-02。
触发：用户要求首次编辑宣传演示，明确选用英文、浅色建筑设计感，并加强首页的空间几何与空气流线。
备选：科学可视化深色主题、Apple 产品浅色主题、建筑设计浅色主题。
选择：16:9 白 / 冷灰底、石墨色 Arial 排版、克制青色；首页使用建筑剖透视与概念流线，内容页保留留白和原生可编辑的表格、连接图与命名布局。
影响：采用 12 页路演框架；视觉概念与已实现 / 待开发能力分开，真实比较结果在验证后补入。这个选择不改变求解器、模型或产品阶段。
验证证据：`PitchDeck.pptx`、`PitchAssets/style-guide.json`、`PitchAssets/imagegen-prompts.json`；最终文件全部页面重导入渲染，包结构和布局检查通过。

## 待决定

- N1-01：按ADR-018实施独立analysis DTO/schema与侧文件约定；最终tag字节表/API、共享项目变化兼容仍在代码实施时验证并冻结。
- N1-02/N2：实际两端RealityView相机/选择、最低系统回退验收与渲染预算。
- N3：展示档案具体数值/来源和资源预算；未经校准不增加单位速度。
- N4：具体功率/围护/费率来源与可支持情景；N5：PDF实现与发行渠道。
- N6：独立测量、RC/原生网格的适用性；恢复外部求解时重新确定权限/基准。

每条新增决策记录触发原因、备选、选择、影响、验证证据与日期。原引擎待决定项可在N6恢复时重新打开。

## ADR-010：复用 Colima 的 arm64 OpenCFD 与原生 EnergyPlus（目标已接受，执行待验证）

日期：2026-10-02；任务 P1-01。触发：本机 arm64 / 32 GiB，现有 Colima 0.10.3、Lima 2.1.4、Docker CLI 29.6.2，但无运行 VM/daemon 和可发现引擎；P1-02…04 需要固定发行身份、版本与架构。

备选：原生 Mac OpenFOAM 源码构建、x86 Linux 模拟执行、全新 VM/远程节点、现有 Colima arm64 容器；EnergyPlus 原生 Mac 或另建 Linux 安装。选择：现有 Colima/Docker 提供 Linux arm64 OpenCFD v2506 镜像，使用 registry 核实的 arm64 子 manifest digest（见 runtime manifest）；EnergyPlus 26.1.0 / build 6f2e40d102 的官方 macOS13 arm64 tar.gz，固定官方资产 SHA-256。Python 固定现有 3.13.7 和项目独立环境/已有 dependency lock。推断依据：复用现有工具减少维护环节；原生 arm64 避免引入 x86 模拟执行；EnergyPlus 官方 native 包免去本轮定制镜像。该选择没有性能测量结论。

OpenFOAM 2412/2506/更新版本均存在，选定 2506 的可核实 arm64 镜像身份作为首个固定基线；EnergyPlus 26.2.0 刚发布，本轮冻结 26.1.0。候选 `buoyantSimpleFoam` 的官方 v2506 说明覆盖稳态浮力/湍流/传热；能否满足室内非等温射流由 P1-02 独立基准判定，网格/湍流/近壁面策略仍未决定。

官方查询日期 2026-10-02：[OpenCFD v2506](https://www.openfoam.com/news/main-news/openfoam-v2506)、[镜像 tags](https://hub.docker.com/r/opencfd/openfoam-dev/tags?name=2506)、[v2506 solver 源码索引](https://api.openfoam.com/2506/files.html)、[EnergyPlus 26.1.0](https://github.com/NatLabRockies/EnergyPlus/releases/tag/v26.1.0)、[Colima](https://github.com/abiosoft/colima)。具体 digest、资产字节数与 API 来源见 Backend/Runtime/README.md 与 manifest。

影响：只选这一条主路线；doctor 不安装、不联网、不切 context、不启动 VM，不改变系统设置或 App sandbox；iOS 不承载任何进程/容器路径。daemon/kernel/VM guest 身份未发现，内存最低值保持 null，P1-05 实测再定。镜像不含 tutorials，P1-02 必须另固定来源；case/weather/output 布局仅声明未实现。安装批准后严格 doctor 和真实引擎版本/启动证据齐全才标 P1-01 完成；版本升级重新记录并验证。

## ADR-011：兼容的环境诊断与计算能力分离（已接受）

日期：2026-10-02；任务 P1-01。触发：P0 doctor 硬编码引擎状态无法解释本机环境，也不能把外部命令可执行当作管线完成。备选：覆盖 P0 字段、升级整个项目协议、为 CLI 添加独立环境报告。选择：保留 protocol_version 1 / scaffold / 四级 not_configured，新增 environment.report_version 1；目标配置与发现值分开，状态和提示明确，未知用 null；严格退出作为显式选项。诊断只在用户 CLI 调用，默认退出 0 保留旧行为，blocked 的 strict 退出 2，配置错误 JSON 退出 3。

影响：项目/请求/receipt/Swift Codable 不变；新增独立 snake_case schema 和协议说明。标准库 SystemProbe 的进程执行可注入，有限超时、局部进程树终止、独立 bounded Docker 清理；解析后的指定字段进入报告，原始 stderr/凭据/私人路径不输出。任何引擎 startup 通过也保持 simulation_pipeline=not_implemented、physical_validation=not_performed。证据：doctor 行为/CLI/schema 测试、真实无引擎诊断和 contracts 回归，见 verification.md。

## ADR-012：原生包文档与完整值编辑事务（2026-10-03，已接受）

触发：P2 编辑、保存与候选隔离需要一份持久化权威，避免工作区镜像、文件和 undo 分别修改输入。备选：手动路径保存、平台文档对象、SwiftUI FileDocument。选择：两端 DocumentGroup + Sendable FileDocument，binding 为持久化权威；WorkspaceStore 注入发布与容量预检，完整项目值事务含基准/模板 bookkeeping，最近 60 次会话撤销；选择和输入快照不持久化。Core 物理模型保持 Foundation-only，包元数据在 Workspace，worker 当前只消费 v2 输入而不解析项目包。

影响：原生协调保存不叠加手工原子写；独立导出先完成序列化再原子写。附件作为不透明值保留，天气在会话内追加以支持 undo/redo；未来大场需流式 artifact store。Mac JSON 生成新文档；iOS 缺少同一 newDocument API，以独立导入修复会话导出新包，保持原文档独立。证据：包真实磁盘关闭重开、失败保存原文件不变、未知扩展精确保留、天气哈希与预算边界、整合事务测试；原生保存和最近项目重开，见 verification.md。

## ADR-013：显式假设与逐项修复的 P2 编辑器（2026-10-03，已接受）

触发：导入错误项目需要可修复，又不能让编辑静默猜测物理输入或覆盖其他方案。选择：本地文本草稿 + 显式 Apply/Cancel；新增输入默认未知，未表达 unknown 的 exposure/boundary 配置保持缺失。模板布局与时间段记录内部版本化假设，覆盖项为用户输入；设备性能、热源、气象和费用保持未知。

完整性错误通过代码、方案 UUID、实体 UUID、字段路径和计数比较，逐项修复可保留既有问题但不引入新问题；计算准备只检查所选方案并叠加包资产检查。重复/悬空条件保留原值顺序和来源，显式选择/删除/冲突清理；外部更新或 undo 后过期草稿不提交。共享几何检查所有方案。采用数值编辑与俯视点击、可访问对象列表，拖拽/任意几何/3D 手柄后续推进；风口输入箭头不是 CFD。证据：跨方案错误转移拒绝、无关编辑无损、显式修复、快照独立、投影往返、源值保留测试及双端编译。

## ADR-014：Swift本地工具为首版主线（2026-10-03，已接受）

触发：用户指出交付链路过长、消费者不适合配置Linux/等待求解、输入依据不足，并要求重构Plans为Swift本地规则和RealityKit方向。备选：继续外部CFD关键路径、立即重写完整Swift CFD、先做本地规则与限定估算。选择：复用P2，N1契约→N2三维+N3路径规则→N5离线交付；N4可延期，N6按独立数据扩展。

影响：App日常不依赖Python/Linux/容器；保留Backend代码/锁定配置/测试与历史P1部分成果。外部求解退出首版前置，不声称其任务完成；不同输入依据开放不同能力。证据：本轮用户要求、现有源码/交付记录盘点、更新后的主线计划；没有新算法/性能/物理运行证据。

## ADR-015：规则预览与定量估算分别标注（2026-10-03，已接受）

触发：详细求解器不能补出未知物理边界，视觉逼真也不能证明现实准确。选择：N3只提供版本化假设方向/扩散路径、遮挡和几何关系；N4在输入就绪时给集总热量/功率时段情景。保留未知与来源，不用任意默认系数给座位温度、舒适、换气或节能结论。

影响：单位速度、温度场、PMV/PPD、年度收益和物理验证级别延后；规则检查通过只代表方法实现符合规格。碰撞处终止并说明未计算绕流，展示动画时钟不等于空气/降温时间。证据：方法规格与验证反例；EnergyPlus热平衡/NIST均匀分区边界依据见来源登记。尚无射流校准。

## ADR-016：RealityView非AR与现有最低系统（2026-10-03，已接受）

触发：用户要求三维模型查看，当前macOS14/iOS17基线低于RealityView15/18 availability。备选：直接提高最低版本、并行维护多套3D renderer、现代系统RealityView且旧系统完整二维回退。选择：第三条；使用virtual camera，不要求摄像/扫描，N1-02先实际验证。

影响：本轮不改Package/xcconfig；N2隔离availability/capability，15/18起三维，14/17二维和本地分析。若后续决定所有受支持系统都具备三维，再单独评估兼容成本或最低版本。证据：Apple文档和本机SDK公开接口核对，见来源登记；双端实际渲染仍待实现/验证。

## ADR-017：任务编号与契约兼容（2026-10-03，已接受）

触发：已有P2提交、P1部分交付和P0协议不能被重规划改写成另一含义。选择：P0/P2保留，P1/P3…P7归档和导向页，新主线N1…N6使用新ID；旧SimulationFidelity和request/receipt不承担规则预览语义。本地AnalysisMethod/版本、请求与结果独立定义。

影响：既有v2输入/包/schema/Python生成同步约束继续有效；分析假设独立ResolvedInput，run结果通过DocumentGroup事务持久化，不直接加未知metadata键。不删除原证据，不升级旧结果等级。证据：迁移清单与新数据契约计划；本轮无协议代码变化。

## ADR-018：N1–N5详细实施约定（2026-10-03，规划采用，代码待验证）

触发：现有阶段只有概览，AI实施可能各自选择请求、缓存、保存和比较方式。选择：保留27个任务ID，以[执行规范](../References/10-ai-execution-guide.md)、阶段工作包和[92项案例](../References/11-native-acceptance-cases.md)统一接口归属与完成门槛。新类型名是实施约定，尚未发布API/schema。

采用独立analysis配置Store及native-analysis run侧文件；包metadata/v2/P0含义不变。区分完整snapshot、方法input、计算缓存、费用评价hash；规范化使用有类型tag的固定字节序列，不声称RFC8785；缓存首版限制方案内，命中新run保留新请求证据。分析配置与P2输入统一undo，结果保存经最新文档值事务，未知附件保留。费用在run的evaluations目录追加并更新manifest索引，固定比较作为独立ComparisonRecord保存；原run input/result不可变，旧引用不借新输入补齐。

气流采用用户明确接受的内部锥状展示档案，密度只改显示；N2自管虚拟相机作为拟实施策略，N1先实际验证。N4功率声明basis与fixed24HourReference窗口，显热先用有来源合计UA，子集清单不做完整容量判断。参数/预算是可版本化实施选择，不是物理系数、性能测量或真实账单依据。

后果：具体步骤与反例可逐项审查，N4继续Should、不阻断核心闭环。需要实际SDK/平台/数据证据的项仍未验证；实施若发现接口不可行，记录对应任务/证据并更新本约定及调用方，不隐式改变原契约或制造有效结果。

## ADR-019：N1实际接口与N2相机策略（2026-10-03）

N1实现采用五份独立native schema及Core DTO；真实Swift输出以锁定独立validator交叉校验，原P0/v2/package含义不变。canonical v1的具体tag表和golden写入Protocols/native-analysis-v1，CryptoKit仅在Simulation。actor只记账，hash/算法/大结果编码后台执行；有界产量stream保留唯一终态，runID会话防重表上限65,536，超限明确拒绝而不遗忘旧身份。

非ARprobe实际自管PerspectiveCamera实体在Mac和iPad可见，Mac按钮改变视角与选择已观察。N2按详细计划采用单一自管相机，native controls设none；native orbit/dolly为能力探索，不与自管状态同时控制。三维手势仍需N2自己的实际证据，旧系统继续完整二维回退，不提高部署最低版本。实际API映射见N1交接；费用/固定比较的独立记录留N4/N5，不改变immutable原run。

## ADR-020：N2生产输入与旧画面归属（2026-10-03）

N2实现采用单一自管PerspectiveCameraComponent及明确vertical FOV，SwiftUI画布输入层负责点选/拖动/捏合，Mac滚轮只在所属window/viewport处理。显示射线由同一CameraState和实际视口生成，对当前可见descriptor取最近对象；它仅服务UI选择，气流碰撞由N3独立纯规则实现。原SDK碰撞/InputTarget保留，native orbit/dolly不与生产相机同时控制。

每个视口有独立controller，不共享Entity。后台构建冻结完整RoomSceneBuildInput；输入变更期间保留旧画面/相机，但禁用旧画面的选择/旧几何编辑入口。新的descriptor完成后再恢复；不能只核对projectID或嵌套UUID，防同nested ID候选误选。更新单个对象依稳定节点diff复用其他实体，不用scenario `.id`强制重建相机。

证据：124项共享Swift+Extension2、两端构建；Mac实际点选、drag/wheel/top/focus/reset、P2属性应用/撤销及强制二维通过；现代iPhone/iPad实际渲染。N1诊断probe的公开射线/系统手势仍受限，不将生产选择成功等同该诊断方法或所有平台通过。具体SDK依据与接口见[N2交接](N2-implementation.md)。最低系统/可访问性/性能未验项保留台账；N2逐段最小overlay由N3合并后再验满预算。

## ADR-021：N3规则场、身份与有限图层（2026-10-03）

N3生产方法采用明确接受的genericCone v1：无量纲场、确定性Halton、闭边界slab首次碰撞及BVH候选加速；最早t按全局最小值集合确定，容差内稳定UUID选取，不以遍历顺序改变遮挡。0.05m/12°及衰减是内部展示假设，仍未经现实校准；墙内向epsilon与碰撞容差分别记录。

同一不可变结果生成3D/2D，后台准备每路径合并mesh，主线程安装最多64个实际递归路径实体。首版静态，无ticker；可选动画延期。每窗coordinator通过当前scenario/hash/request控制阶段与图层，App共享client全局2/8预算。完整ProjectValidator门槛不降级；优化只移除重复序列化/校验工作，公开codec仍严格检查结构、语义、hash与包预算。

证据：N3代理165共享Swift+Extension2、39Python、native17真实记录/10拒绝变异及两端构建；Mac实际采用/遮挡/三候选/undo/系统导出与退出新进程恢复。Release典型client p95约75ms，满预算约520ms仍未达到200ms，GPU FPS与App峰值未验。重开自动按需恢复、同ID文档实例隔离与日常面板主线程刷新成本继续N5审查，不把分析方法检查当物理准确度。

## ADR-022：N1～N4最终范围与会话隔离（2026-10-03，代码与自动回归通过）

用户将目标缩为N1～N4，仍含N4全部Should任务。N5消费者分享/PDF/ComparisonRecord/发行候选保留计划，不在本次新增；已有运行取消、文档替换、当前结果归属和主线程刷新缺陷仍在本次修复。

文档采用不序列化的documentInstanceID：同一次打开的完整值事务保留，独立读取即使projectID相同也生成新实例；nativeSidefileRevision继续独立标记附件变化。完成事件先后台严格验证，再核对identity/sequence/generation；结果封装保存任务句柄并传播取消，返回后重核会话。未变项目/元数据复用验证基线，公开值修改、编辑与保存仍执行完整检查。根新增10项生命周期、实例、缓存依据、重复序号及撤销回归均通过；冻结最终源码201项共享Swift、完整契约与双端构建通过。实际界面、最低运行时及可访问性仍缺证据，不据此宣称整体完成；详[N1～N4最终审查](N1-N4-final-review.md)。
