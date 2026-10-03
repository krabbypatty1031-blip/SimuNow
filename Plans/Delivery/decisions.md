# 架构决策记录

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

## ADR-014：run 目录位置与 worker 显式配置（已接受）

日期：2026-10-03；任务 P3。触发：P3 需要独立 run 目录存放 input.json/events.jsonl/result.json；目标布局（项目包内 runs/<run-id>/）依赖包的持久写入权限，而 Mac sandbox 下项目包的用户授权访问不跨会话保留（当前 recents 只存路径，重开需重新选择）。

备选：直接写项目包 runs/ 子目录；Application Support 按项目/方案/run ID 分层；临时目录。选择：本阶段写 `~/Library/Application Support/SimuNow/Runs/<projectID>/<scenarioID>/<runID>/`（sandbox 始终允许），P7 打包/书签方案落地后按 ADR 迁移到项目包内；每个 run 只写自己的目录，worker 与客户端都不越界。worker 位置不猜路径：仅 UserDefaults（simunow.worker.python / simunow.worker.src）或 SIMUNOW_WORKER_PYTHON / SIMUNOW_WORKER_SRC 环境变量显式配置，未配置则界面显示修复指引并指向 doctor，不产生假执行。

影响：旧 run 在 App 重启后可从目录扫描恢复（无 result.json 的目录标记为「已中断」）；iOS 无本地执行器，为 UnavailableRunClient。证据：RunStore 测试（提交/陈旧/重载/中断/取消）、LocalSimulationClient 真实进程集成测试、verification.md P3 节。

## ADR-015：doctor 增加 L0 真实自检（已接受）

日期：2026-10-03；任务 P3。触发：P3 计划要求「L0 为纯 Python，环境满足即 verified_available（真实执行一次自检计算）」；P0 的 engines.l0=not_configured 硬编码已不符合现实。

选择：doctor 在进程内对固定最小自检快照真实执行两次 L0 适配器，核对确定性、质量状态与关键指标；结果写入新增顶层 `l0` 对象并镜像到 `engines.l0`（verified_available / probe_failed / not_configured）。doctor 核心保持仅标准库可导入（自检惰性导入锁定依赖，缺失即 not_configured）。`--strict` 语义不变：仍只由 environment.status 决定，L0 自检是管线 sanity 信号而非环境门槛。physical_validation=not_performed 不变——自检不是物理验证。

影响：doctor-report schema 的 engines.l0 由 const 改为枚举，新增顶层 l0 对象；ADR-011 的兼容语义中「四级 not_configured」自此只适用 l1/l2/l3。证据：test_doctor 新增 3 项自检测试、真实 doctor 输出（l0 verified_available，environment blocked）、contracts 回归。

## ADR-016：基础 PDF 报告用 CoreGraphics 文本排版（已接受）

日期：2026-10-03；任务 P5-04。触发：比赛链路需要可导出的基础报告；P5 阶段计划要求本阶段决定并锁定 PDF renderer。

备选：ImageRenderer 截图式导出（位图，文本不可选不可搜索）；引入第三方 PDF 库（新依赖）；CoreGraphics PDF context + CTFramesetter。选择：CoreGraphics/CoreText 文本排版（A4、分页、系统字体含中文 fallback、文本可选中），无新依赖，双平台可用。报告内容来自固定 ReportContent 快照（ReportBuilder 只做格式化，不重算指标）；无有效 run 时导出被阻止并解释。

影响：报告版式为清晰基础版；图表/复杂排版在后续阶段增强。证据：ReportTests 的 PDF 有效性测试（%PDF 头、分页对象、非空）与 verification.md P5 节。

## ADR-017：提前接入只读 3D 几何预览（已接受）

日期：2026-10-03。触发：用户审阅 App 后指出建模视图只有俯视 2D；P2 计划将「3D 手柄」后置（编辑性 3D 交互仍后置），但只读几何预览与编辑器不同，可以提前。

备选：等 P4 连同场渲染一起做；现在就做完整 3D 编辑手柄；只读预览。选择：只做**只读 3D 几何预览**——RealityKit 渲染房间/开口/家具/座位/采样点/送回风方向箭头，拖动旋转与缩放，编辑仍全部走俯视+表单。SDK 事实：Xcode 27 中 RealityView 为 macOS 15+（非此前以为的 14），因此按 ADR-002 以 availability 分级：macOS 15+ 显示预览，更低系统与 iOS 17 显示诚实回退说明，最低部署版本不变。

影响：预览不含任何气流/温度场，界面常驻文字声明；布局数学（RoomPreviewLayout）为纯函数可测。P4 场视口仍按原计划在渲染层统一接入（切片/流线届时复用坐标与布局基础）。证据：RoomPreviewLayoutTests（几何映射/拒绝未知尺寸/相机数学/指纹稳定性）、`check.sh all` 全绿、App 启动验证。

## ADR-018：P1-01 运行时自包含安装与探针修正（已接受）

日期：2026-10-03；任务 P1-01 收尾。触发：用户授权安装引擎，要求下载物便于清理。

选择：所有工具与数据放入 `Backend/RuntimeLocal/`（gitignore 已排除）：colima/lima/docker CLI 二进制、LIMA_HOME（VM 与 guest 镜像与容器层）、DOCKER_CONFIG、EnergyPlus 解压目录；`env.sh` 提供 source 入口。清理 = 停 VM 后删除 RuntimeLocal 与 ~/.colima（colima 小体量 profile 固定位于后者，实测 COLIMA_HOME 不影响 profile 位置）。版本严格按 manifest：colima 0.10.3、limactl 2.1.4（对上游 SHA256SUMS 校验）、docker 29.6.2、OpenFOAM digest 不变、EnergyPlus 26.1.0（SHA-256 匹配）。

执行中发现并修复两个 doctor 真实 bug（此前只有模拟探针覆盖）：① inventory 版本正则不匹配 `colima version v0.10.3` 的 v 前缀（`\b` 在 v 与数字间无边界）；② OpenFOAM 探针把 bashrc 路径作为位置参数传入容器，OpenFOAM 配置链会对 `$1` 指向自身的 bashrc 递归 source（~11 秒后 SIGSEGV）——改为脚本内嵌字面路径。同时修正 manifest 的 `version_command`：该 v2506 镜像不含 `foamVersion`，版本/发行方改从 `buoyantSimpleFoam` 横幅解析（schema 与 manifest 同步）。

影响：strict doctor 在本机 exit 0 / status=ready，容器/架构/镜像身份/版本/最小启动/清理全部真实验证；P1-01 完成。VM 配置 4 核/6 GiB 为研发初始值，非物理最低要求（P1-05 实测再定）。证据：Artifacts/P1-01/ 与 verification.md。

## 待决定

- P1：固定路线的执行验证；候选求解器的基准适用性、网格与湍流，EnergyPlus 设备模型。
- P3：Mac helper/companion 运行时和权限桥接（sandbox 下 App 内执行 worker），事件/重启策略。
- P4：renderer 及各平台预算、舒适档案与边界。
- P5：成本数据来源；P7：代理/远程/发布渠道。

每条新增决策记录触发原因、备选、选择、影响、验证证据与日期。

## ADR-010：复用 Colima 的 arm64 OpenCFD 与原生 EnergyPlus（目标已接受，执行待验证）

日期：2026-10-02；任务 P1-01。触发：本机 arm64 / 32 GiB，现有 Colima 0.10.3、Lima 2.1.4、Docker CLI 29.6.2，但无运行 VM/daemon 和可发现引擎；P1-02…04 需要固定发行身份、版本与架构。

备选：原生 Mac OpenFOAM 源码构建、x86 Linux 模拟执行、全新 VM/远程节点、现有 Colima arm64 容器；EnergyPlus 原生 Mac 或另建 Linux 安装。选择：现有 Colima/Docker 提供 Linux arm64 OpenCFD v2506 镜像，使用 registry 核实的 arm64 子 manifest digest（见 runtime manifest）；EnergyPlus 26.1.0 / build 6f2e40d102 的官方 macOS13 arm64 tar.gz，固定官方资产 SHA-256。Python 固定现有 3.13.7 和项目独立环境/已有 dependency lock。推断依据：复用现有工具减少维护环节；原生 arm64 避免引入 x86 模拟执行；EnergyPlus 官方 native 包免去本轮定制镜像。该选择没有性能测量结论。

OpenFOAM 2412/2506/更新版本均存在，选定 2506 的可核实 arm64 镜像身份作为首个固定基线；EnergyPlus 26.2.0 刚发布，本轮冻结 26.1.0。候选 `buoyantSimpleFoam` 的官方 v2506 说明覆盖稳态浮力/湍流/传热；能否满足室内非等温射流由 P1-02 独立基准判定，网格/湍流/近壁面策略仍未决定。

官方查询日期 2026-10-02：[OpenCFD v2506](https://www.openfoam.com/news/main-news/openfoam-v2506)、[镜像 tags](https://hub.docker.com/r/opencfd/openfoam-dev/tags?name=2506)、[v2506 solver 源码索引](https://api.openfoam.com/2506/files.html)、[EnergyPlus 26.1.0](https://github.com/NatLabRockies/EnergyPlus/releases/tag/v26.1.0)、[Colima](https://github.com/abiosoft/colima)。具体 digest、资产字节数与 API 来源见 Backend/Runtime/README.md 与 manifest。

影响：只选这一条主路线；doctor 不安装、不联网、不切 context、不启动 VM，不改变系统设置或 App sandbox；iOS 不承载任何进程/容器路径。daemon/kernel/VM guest 身份未发现，内存最低值保持 null，P1-05 实测再定。镜像不含 tutorials，P1-02 必须另固定来源；case/weather/output 布局仅声明未实现。安装批准后严格 doctor 和真实引擎版本/启动证据齐全才标 P1-01 完成；版本升级重新记录并验证。

## ADR-011：兼容的环境诊断与计算能力分离（已接受）

日期：2026-10-02；任务 P1-01。触发：P0 doctor 硬编码引擎状态无法解释本机环境，也不能把外部命令可执行当作管线完成。备选：覆盖 P0 字段、升级整个项目协议、为 CLI 添加独立环境报告。选择：保留 protocol_version 1 / scaffold / 四级 not_configured，新增 environment.report_version 1；目标配置与发现值分开，状态和提示明确，未知用 null；严格退出作为显式选项。诊断只在用户 CLI 调用，默认退出 0 保留旧行为，blocked 的 strict 退出 2，配置错误 JSON 退出 3。

影响：项目/请求/receipt/Swift Codable 不变；新增独立 snake_case schema 和协议说明。标准库 SystemProbe 的进程执行可注入，有限超时、局部进程树终止、独立 bounded Docker 清理；解析后的指定字段进入报告，原始 stderr/凭据/私人路径不输出。任何引擎 startup 通过也保持 simulation_pipeline=not_implemented、physical_validation=not_performed。证据：doctor 行为/CLI/schema 测试、真实无引擎诊断和 contracts 回归，见 verification.md。

## ADR-012：开发机 Python 固定版本 3.13.7 → 3.13.16（已接受）

日期：2026-10-03。触发：当前开发机（tanchai）无 3.13.7；Homebrew 3.13 系列瓶装版本为 3.13.16，精确编译 3.13.7 需要额外工具链。备选：pyenv 源码编译 3.13.7、改用 3.14、升级固定到 3.13.16。选择：固定 3.13.16（Homebrew python@3.13），manifest、test_doctor 同步更新；requirements-dev.lock 不变。影响：与原固定路线同为 CPython 3.13 补丁级差异；doctor 环境检查在本机 python_matches=true。证据：2026-10-03 本机 24 项 doctor 测试与 contracts 全部通过，见 verification.md。其他固定目标（Colima/OpenFOAM/EnergyPlus）不变；本机尚无容器工具，P1 引擎验证条件不变。

## ADR-020：3D 预览使用手搓示意外形（已接受）

日期：2026-10-03。触发：只读预览里的家具、座位和空调都是方块。备选：下载现成模型；继续用方块；按现有位置手搓示意网格。选择：在 RealityKit 里用方块、圆柱和球体拼出桌子、椅子、坐姿人体、显示器、门窗框和壁挂空调。人体和椅子的尺寸是显示约定，不是测量值；桌子使用障碍物已有的包围尺寸。不把这些外形写入负荷或风量。影响：办公室模板能看到桌、椅、人和显示器；教室模板能看到椅子和人。证据：RoomPreviewLayout 仍只做坐标映射，人数与朝向由测试核对。

## ADR-019：建房默认使用香港大学 10 月气候（已接受）

日期：2026-10-03。触发：办公室模板因朝向、外墙边界温度、室内外温湿度、代表日、时区和天气引用未填而不能估算。备选：继续留空由用户逐项填写；编造一组无来源数字；把香港天文台月平均写成默认并标明来源。选择：办公室、教室模板和建房向导在创建时写入香港天文台 1991–2020 年 10 月月平均（气温 25.7°C、相对湿度 73%），代表日 2026-10-15，时区 Asia/Hong_Kong，俯视图远侧（+Y）暂按正北。测站是尖沙咀，用于香港大学本部（薄扶林，约 22.284°N、114.138°E），不是校园实测。室内湿度暂用室外月平均，并写明不是室内实测。外墙边界温度是墙外空气温度，不是墙面温度。天气引用指向这份说明的 SHA-256；L0 仍只用恒定室外温度，不读取逐时天气文件。保存项目时把说明写入包内 `climate/hku-october-1991-2020.txt`。向导的空调和通风仍待填。影响：新建模板可以直接做 L0 估算；改朝向、改日期或改测值会替换这些预设。证据：模板与向导测试、引用文件哈希一致。

## ADR-013：P2 项目包与窗口策略（已接受）

日期：2026-10-03。触发：P2-04 需要保存/导入；文档窗口生命周期是 P2 待决定项。备选：DocumentGroup/ReferenceFileDocument 文档架构、WindowGroup + 显式打开/保存面板。选择：WindowGroup + 显式面板 + 原子写入；项目包为单文件 `project.json` 的 `.simunow` 目录包；多窗口各自管理各自项目，无共享可变状态；本阶段不提供结构性撤销/重做（文本编辑走系统原生；删除有确认）。理由：文档架构重构改变 P0 已验证的入口结构，在本机无 UI 自动化验证的条件下风险高于收益；runs/、measurements/ 等子目录在 P3/P6 接入时扩展包格式并记录。影响：最近项目列表自行维护（UserDefaults 书签）；撤销范围在 P5 产品加固时重估。证据：P2 执行计划与验收记录。
