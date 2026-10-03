# 工程验证记录

## N5/N6 提交前复核（2026-10-03）

用户追加授权提交、推送本工作区 N5/N6 实现，并通过 PR 合并 UI 修复。提交基点为 `eda5d5c`；保留既有演示稿、共享 scheme 和未知项目附件。

- 重新执行 Linux Foundation harness：17 项真实 Swift 核心/值层测试通过；8 份真实 Swift wire 及 17 个拒绝反例通过独立 Python 契约校验。
- 重新执行 Backend 测试：44 项通过；项目模型、本地分析、消费者证据及 Python schema 生成检查无漂移；`git diff --check` 通过。
- 当前环境没有 Xcode；这次复核不提供 Apple SDK 编译、PDF 页面、RoomPlan 真机或 UI 操作验收证据。
- UI 分支须在可读取的远端取得后再做差异审查、冲突处理和 PR 合并；本次 N5/N6 提交不代表 UI 修复已整合。

路线说明（2026-10-03）：下文已有构建/运行/环境记录为对应日期事实。旧P1安装“下一步”属于当时引擎路线；当前开工按Plans/README的N1–N6，未产生本地分析/RealityKit运行证据。

日期：2026-10-02；环境：Apple Silicon Mac、Xcode 27.0 (27A266a)、Xcode Swift 6.4、macOS/iOS SDK27。
工程最低 macOS14/iOS17、Swift6模式；最低系统实机运行尚待验证。

## 最终目录验证结果

验证从 `/Users/pacoramirez/Desktop/SimuNow` 执行，确认本地包和文件使用相对路径，工程可搬移。

| 检查 | 结果 | 说明 |
|---|---|---|
| pbxproj 语法与共享 scheme XML | 通过 | plutil 与 XML 解析 |
| Swift Package 测试 | 通过，3项 | draft round-trip、旧 run 新鲜度、未配置引擎拒绝成功 |
| SimuNowMac Debug | BUILD SUCCEEDED | 当前 Apple Silicon 架构，关闭签名构建 |
| SimuNowiOS Debug | BUILD SUCCEEDED | generic iOS Simulator，不需要开发团队 |
| Mac 启动与界面 | 通过 | 空工作区、sidebar、inspector、报告空状态可见 |
| Xcode 打开工程 | 通过 | 两端 shared schemes 与本地包可见 |
| 文档本地链接 | 通过 | 21份计划文档，无失效相对链接 |
| Python doctor | 通过 | worker正常，四级引擎均明确 not_configured |
| iOS实际启动/真机/最低系统 | 未验证 | 编译通过不等于设备运行验证 |
| CFD/能耗/扫描/报告物理能力 | 尚未实现 | 依对应阶段推进 |

最终构建命令：`Scripts/check.sh all`。共享包使用 Swift Testing，日志中的 XCTest 0项不代表未测试；后续 Swift Testing 输出确认3项通过。
Mac 观察显示报告空状态的三栏布局，未展示任何数值结果。用户可在 Xcode 选择 SimuNowMac / My Mac 运行。
构建中的 AppIntents metadata 未抽取提示属于当前没有依赖 AppIntents 的说明，不阻断构建。

## 验证范围

项目结构、共享包契约、macOS Debug 和 generic iOS Simulator 编译、worker 能力探测。
当前没有物理求解器、扫描、真机或报告实现，不能视为这些能力验证。

## 环境处理

系统命令行默认 CommandLineTools；脚本显式设置 DEVELOPER_DIR，不修改全局选择。
Desktop/Documents 的 File Provider 属性可影响测试 bundle 签名，因此脚本默认使用临时构建目录。
Debug 设置 ONLY_ACTIVE_ARCH=YES，保持 App 与本地包架构一致；Release 仍使用默认多架构设置。


## P2-01 验收（2026-10-02）

本轮实现项目输入基座，不改变物理阶段状态。与原 P0 验证共用 Apple Silicon/Xcode 环境；临时独立 Python 3.13 环境使用 requirements-dev.lock（pydantic 2.13.4、jsonschema 4.26.0 及锁定传递依赖）。

实际验收命令：`SIMUNOW_PYTHON=/tmp/simunow-p2-venv/bin/python Scripts/check.sh all`，退出码 0。复现时可按 Backend/README.md 建立 Backend/.venv 后运行 `Scripts/check.sh all`，无需沿用临时路径。另执行 `PYTHONPATH=Backend/src python3 -m simunow_worker doctor`。

| 检查 | 结果 | 证据与范围 |
|---|---|---|
| 生成结构/schema 漂移 | 通过 | generate_domain_models.py --check、models.schema --check |
| Python 单测 | 14 项通过 | 严格解析、独立 Draft202012Validator、迁移、完整性、精确未知值、快照、注册/规则/几何扩展 |
| Swift Testing | 16 项通过 | SimuCoreTests 14 项（含 P0 原有 3 项）+ 独立 SimuExtensionTests 2 项 |
| 跨语言真实交换 | 通过 | Python→Swift→Python 和 Swift→Python→Swift；2 份项目/快照、28 类语义错误或未知扩展，另有结构/损坏输入拒绝 |
| 未知 payload | 通过 | 数值 token 保留大整数和高精度小数；不支持类型阻断准备，不冒充已知类型 |
| OCP | 通过 | 独立设备实现/schema/注册及额外规则覆盖项目与快照；自定义几何查询作用于校验 |
| macOS Debug | BUILD SUCCEEDED | CODE_SIGNING_ALLOWED=NO；共享模型和 schema 资源集成 |
| generic iOS Simulator Debug | BUILD SUCCEEDED | CODE_SIGNING_ALLOWED=NO；最低目标仍为 iOS17 |
| doctor | 通过 | scaffold；l0/l1/l2/l3 均 not_configured |
| 本轮 App 启动/真机/最低系统 | 未验证 | 编译不能替代运行 |
| 求解/守恒/舒适/能耗物理验证 | 未实现 | 输入一致性校验不是求解质量证据 |

日志位于忽略的 `Artifacts/P2-01/check-all.log` 和 `doctor.json`。AppIntents metadata 提示与 P0 一致：当前无该框架依赖，不阻断构建。测试 fixture 是人工接口数据，天气路径与全零哈希不对应真实资产。

## P1-01 环境检查部分交付（2026-10-02）

目标分支 paco-development；单 Agent。已有演示稿、iOS scheme 及 Pitch 文档改动保留，不包含在本轮提交中。初次交付时未提交/推送，后续按用户明确授权提交；没有下载引擎/镜像或启动 VM。本轮改动仅 Backend、CLI/schema、检查脚本和文档；未修改共享 Swift 或平台入口，因此没有重跑 Mac/iOS 编译，也未新增 App 启动证据。

本机：`sw_vers` 得 macOS 27.0 / build 26A428；`uname -m` 得 arm64；允许的只读 `sysctl -n hw.memsize` 得 34359738368（32 GiB）。Python 3.13.7；新建 Backend/.venv 并以 requirements-dev.lock 安装全部固定依赖（小型已有模型/测试依赖，非计算软件）；pydantic 2.13.4、jsonschema 4.26.0。环境与目标分离见 Backend/Runtime/README.md。

| 命令/检查 | 结果 | 证明范围与证据 |
|---|---|---|
| docker --version；colima version；limactl --version | 29.6.2 / 0.10.3 / 2.1.4 | 仅 CLI/工具已安装，不证明 VM/daemon 可用 |
| colima status；docker info（指定字段） | 非零退出；not running / cannot connect | runtime 不可连接；实际 Linux 架构、VM 内存、server version 未知 |
| limactl list（只选状态/架构/CPU/内存字段） | 退出 0，无实例；No instance found | 未发现现有实例；不推断其他外部 VM 不存在 |
| PATH 与常见安装目录检查 | foamVersion/buoyantSimpleFoam/energyplus 未发现；Podman/Multipass PATH 缺失 | 未发现所选命令/常见安装项；镜像库存因 daemon 不可连接而未知；远程节点未配置、未探测凭据 |
| 官方 GitHub API + Docker Registry 公共元数据 | 26.1.0 非 prerelease；资产 SHA-256；2506 index/arm64 manifest 及响应 SHA-256 核实 | 只验证发行身份/目标架构/固定下载内容；无本机安装或执行证据。source-metadata.json、energyplus-release.json |
| Backend/.venv/bin/python -m pip check | No broken requirements found | 独立依赖环境一致；venv-install.log 留安装记录 |
| PYTHONPATH=Backend/src:Backend/tests Backend/.venv/bin/python -m unittest test_doctor -v | 24 项通过 | 无引擎、匹配/失配/构建、架构/身份、缺少命令、daemon、权限、子进程错误/超时/树终止、容器清理、配置结构/重复键、输出/退出和独立 schema；模拟 Probe 不证明引擎可用 |
| Scripts/check.sh contracts | 退出 0 | Python 38 项（14 原有 + 24 doctor）、Swift 16 项、生成漂移/schema、2 项目/快照双向交换与 28 错误/兼容案例；contracts.log |
| PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor | 退出 0，单行有效 JSON，无 stderr | environment=blocked，Python matches；container=unreachable，OpenFOAM=not_configured、image_present=null，EnergyPlus=not_installed；doctor.json |
| 同上加 --strict | 退出 2，单行有效 JSON，无 stderr | 正确阻断环境门槛；doctor-strict.json。四级计算管线继续 not_configured |
| 受限沙盒中的 doctor | 内存 null/权限失败、Docker permission_denied，部分工具可能 timeout | 权限限制单独报告；不据此虚构内存或直接认定 daemon 已停止 |
| 独立 schema 校验真实 doctor / strict 报告和 manifest；git diff --check；bash -n 检查脚本；文档相对链接 | 通过 | 两份实际 JSON 满足协议、manifest 满足 schema/格式约束；无 whitespace/脚本语法/文档链接错误 |
| OpenFOAM/EnergyPlus 真实版本/启动执行 | 未验证 | 没有任何引擎被标记 verified_available；需安装/VM 执行条件 |
| 公开基准、守恒/收敛/精度、天气/设备、性能 | 未实现/未验证 | 属 P1-02…05，不由本轮命令替代 |

第一次 contracts 在当前沙盒中停于 SwiftPM `sandbox-exec: sandbox_apply: Operation not permitted`；允许必要的构建/测试权限后重跑通过。没有关闭系统/App sandbox。官方元数据请求首次受 DNS/证书链限制，改用受允许的系统 curl 信任链访问小型公开 JSON，未禁用 TLS 校验，也未下载镜像层/软件包。

可复现入口为 `Scripts/check.sh runtime`（行为测试+非 strict 本机盘点）、`Scripts/check_runtime.sh --strict`（环境门槛）、`Scripts/check.sh contracts`。doctor 默认不依赖第三方包；严格的完整开发 profile 仍要求独立 Python 和锁定模型/测试依赖。日志全部在忽略的 `Artifacts/P1-01/`，本机信息不写入团队 manifest。

P1-01 尚未完成：目标版本/路线、manifest、doctor 和测试已完成，但 VM/daemon 不可连接、引擎尚无执行证据。下一步批准创建/启动原生 arm64 Colima VM（先核实 guest 下载条件）、拉取固定 OpenFOAM digest（压缩层 340,320,682 字节）、下载并校验 EnergyPlus 官方包（209,850,883 字节）并配置 binary；严格 doctor 成功且真实命令证据齐全后再完成 P1-01。P1-02 独立固定官方基准来源及对比数据，不用人工契约夹具替代物理验证。

本轮修改文件归属（不含已有 Pitch/iOS scheme 改动）：

- Backend：`src/simunow_worker/runtime/{__init__.py,manifest.json,probe.py,doctor.py}` 为目标与探测；`src/simunow_worker/__main__.py` 为兼容 CLI/退出；`pyproject.toml` 打包 manifest；`tests/test_doctor.py` 行为与契约；`README.md`、`Runtime/README.md` 为配置/证据/复现说明。
- 协议：`Protocols/doctor-v1.md`、`Protocols/README.md`、`Protocols/Schemas/{runtime-manifest,doctor-report}.schema.json`。
- 检查：`Scripts/check_runtime.sh`、`Scripts/check.sh`；`.gitignore` 排除本地 RuntimeLocal。requirements-dev.lock 沿用未改，依赖仅安装到忽略的 Backend/.venv。
- 交付：`Plans/Delivery/{status,verification,decisions}.md` 增补 P1-01 事实/证据/ADR，保留既有宣传材料记录。

## P2-02…05 最终整合（2026-10-03）

环境沿用 Xcode 27.0 / Swift 6 模式、macOS 27.0 arm64；最低部署仍为 macOS14/iOS17。四个独立 worktree 在共享基点 `ada63b8` 之上实现、自审并分别编译；根工作区整合后执行以下验证。没有启动 VM、安装引擎、推送代码或关闭 App sandbox。生成器现在保留已有 scheme，原 iOS scheme 的用户定制保留。

| 检查 | 结果 | 范围 |
|---|---|---|
| `Scripts/check.sh contracts` | 退出 0 | Python 39 项；Swift 83 项（81 Core/Workspace + 2 Extension）；生成漂移、2 项目/快照双向交换及 28 类语义/兼容案例 |
| 新包 metadata schema | 通过 | Swift 实际编码输出由 Python Draft202012Validator 独立验证；版本、字段配对、UUID、额外字段与 null 拒绝 |
| 编辑事务与几何 | 通过 | 来源/未知/范围、中间数字不入模型、全部方案碰撞/点位、关联增删、跨方案相同嵌套 ID 的错误不可转移 |
| 草稿与条件修复 | 通过 | 重复/悬空/边界冲突与原始顺序无损、显式删除/恢复/选择、独立方案、缺失记录不自动补齐、过期草稿拒绝 |
| 模板、基准与快照 | 通过 | 新身份、版本化假设、覆盖值来源、基准原子变更、完整几何/metadata 撤销、候选值独立、快照不随编辑改变 |
| 项目包磁盘 I/O | 通过 | 写入关闭重开、未知数值 token/二进制/空目录保留、损坏与未来版本拒绝、非法/失败保存不改原文件、完整预算、符号链接/路径拒绝、天气相对资源哈希 |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | 最终源代码与文档注册，CODE_SIGNING_ALLOWED=NO |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | generic iOS Simulator，含原生浏览与独立 JSON 修复/导出会话 |
| Mac 实际 UI | 部分流程通过 | 空文档、办公室模板、俯视图、对象 AX 列表、方案复制、Cmd-Z / Shift-Cmd-Z；深色当前外观可见 |
| Mac 原生保存/最近重开 | 通过 | 修正 UTI 同时符合 package/content 后，在独立临时 App 副本中保存、关闭、从最近项目重开；1房间、2方案、基准及模板信息保留，两份 JSON 哈希不变 |
| iPad 模拟器安装/启动 | 通过 | iOS26.5 iPad Pro 13-inch M5：simctl install + launch 返回 bundle/PID；编译与进程启动分开记录 |
| iOS实际显示/导入导出、真机、最低系统 | 未完整验证 | 当前 Simulator UI 不可取得，DeviceHub UI 请求超时；没有据此声称交互成功 |
| VoiceOver、大字号、浅色、多窗口并发/文件提供器 | 未完整操作验收 | 可访问性对象/文字状态、布局和草稿冲突代码已实现；单测与编译不代替实际设备检查 |
| 引擎/守恒/收敛/能耗/舒适/成本/报告 | 未实现或未验证 | EPW 头检查、输入几何与质量平衡规则不是物理求解证据 |

原生验收包在临时目录，不进入 Git。保存后和重开后 `project.json` SHA-256 都为 `f97df855d93e592d3a3651ebb943695a89da237913d6d42ff0c8878143486106`，metadata 为 `f40f3ad2460d4f3ca0439cd5539f09e84a32b6fad052391b0d3a760589d4066e`。原生通用打开面板在并存不同注册版本时仍出现禁用选择，最近项目重开成功；干净安装/重启后的通用面板与 iOS 浏览器留待平台操作复验。

实际 UI 检查发现缺少 public.content 导致保存禁用，已按 Apple DTS 文档类型说明补齐并验证保存可用。自动审批拒绝关闭原来含未保存验收状态的窗口；没有终止该窗口，改用临时 App 副本（临时 bundle identifier）保留状态并完成保存验证，不修改项目 bundle identifier。

第一次根测试因 SwiftPM nested sandbox 权限失败，允许项目构建/测试后通过；没有关闭沙盒。新增 metadata 交换文件最初匹配了既有 `*.swift.json` 项目 glob，已改成独立命名并完成回归。AppIntents metadata 提示仍为无依赖框架的非阻断提示。日志保存在忽略的 `Artifacts/P2/`，独立 Agent commits 和审查回执供追踪，工作区变更未推送。

## Swift本地路线计划重构（2026-10-03，仅文档）

- 范围：更新Plans总入口、6份产品/架构/交互/数据/计算/排期参考，新增本地方法规格、迁移清单、来源登记和N1–N6共33个任务；更新验证/平台/风险/状态/ADR，旧路线和Excalidraw归档，P0/P2任务ID保留。
- 官方依据：Apple RealityView/非AR相机文档和本机SDK声明核对为macOS15/iOS18；最低macOS14/iOS17继续二维回退。该检查不代表三维实际渲染通过。EnergyPlus/NIST仅用于热平衡与集总模型边界依据，没有取得新的物理验证。
- 文档验证：49份Markdown、91个相对链接检查，6个N阶段/33个任务编号序列检查均通过；git diff --check通过。归档链接重定位到副本或原协议/事实记录。
- 保留检查：69份现有Swift/配置/工程/scheme文件内容哈希未变；Pitch历史段落与旧verification事实保留；原Excalidraw字节一致存入Archive。现有未提交Pitch材料和iOS scheme未修改。
- 未执行：无Swift/Python/schema代码修改，无新构建/模拟器/规则算法/物理/性能测试，无依赖安装、引擎启动、Commit或Push。已完成P2的旧测试不能当作N1–N6已完成证据。
- 最终审视：新主线不再以P1安装作为前置；预览/估算/测量/经验证求解分别标注；显/潜热、制冷量/电功率、循环风/室外交换分开；无空间温度/PMV/节能承诺；原任务编号没有变义。下一步N1-01与N1-02。

## N1–N5详细计划完善（2026-10-03，仅文档）

- 范围：扩展五个阶段的27项任务，新增共用执行规范与92项验收案例；同步总入口、数据/方法/排期/技术来源、验证、状态与ADR-018。任务ID和Must/Should主线保留，N6不扩大范围。
- 方法审视：按真实P2源码确认旧request/receipt无结果载荷、metadata拒绝额外键、preservedEntries私有更新、document binding权威、严格准备门槛、共享geometry与nested ID作用域、完整输入undo、home枚举和WireSchema支持子集；没有用计划名称冒充已有接口。
- 具体约定审视：配置Store/独立run目录、四类hash与canonical字节、任务取消/终态、有限缓存/包预算、同一输入撤销、外部更新/晚结果、相机能力验证、显示与规则分离、参考24h积分、子集显热与匿名证据均有执行和反例门槛。
- 官方资料：补查公开camera controls/PerspectiveCameraComponent/非AR相机与Swift协作取消；本机SDK声明只用于API核对。实际renderer、任务性能和物理验证尚未执行。
- 文档检查：51份Markdown、148个相对链接均可解析；N1–N5的27个任务及N6保留6项编号连续无重复；92个验收ID唯一且阶段引用全部存在；git diff --check通过。共用规范与阶段的公式/采样/目录/配置/预算/费用评价/比较保存已交叉审视。
- 保留：73份现有应用/Swift/配置/工程文件SHA-256与本次开工快照一致；旧status/verification全部原文保留，Pitch DESIGN-001及既有材料/scheme未修改。
- 未执行：无业务代码/schema修改，无App构建/模拟器/方法/物理/性能测试，无软件安装、引擎/VM启动、提交或推送。92项是待执行验收，不是已通过测试。

## N1–N5实施基线与验证通道（2026-10-03）

- 本次目标完整包括N1…N5，按类别由Subagent规划→实现→自审，根代理顺序整合与最终审查。N1工作树基于216b3ad；其他类别尚未开始，目标保持active。
- 当前主工作区`Scripts/check.sh contracts`退出0：Python39项、Swift83项、生成漂移/schema、2项目/快照双向交换和28类错误/兼容案例通过。日志Artifacts/NativeDelivery/baseline-contracts.log。此为既有P2基线回归，不是N1的新功能证据。
- Xcode27.0/build27A266a；有iOS26.5的iPhone/iPad运行环境，iPad Pro13 M5已启动。受限simctl首次权限失败，授权调试范围内使用必要权限后设备列表和实际截图成功。没有停止VM/用户App或修改全局网络。
- Mac CUA可读现有SimuNow界面；原实例有打开面板，后续测试使用独立临时构建身份以保留其状态。DeviceHub CUA读取两次超时，iOS实际截图已取得但手势交互尚未取得证据。iOS17运行时unavailable，最低系统实际验收未通过；继续实现其他独立项。

## N1实现整合与现代平台初验（2026-10-03）

- 实现范围：独立native DTO/codec/schema、按方法就绪度、canonical/hash、有限调度/取消/LRU、artifact与配置文档事务、统一undo，以及非AR能力probe。准确API/代理自审见[N1交接](N1-implementation.md)。没有生产气流/估算/推荐。
- 根代理整合：精确cherry-pick97d030d为3ea5b56；原计划修改、Pitch和用户iOS scheme保留。审视LocalAnalysisClient、InputResolver、Readiness、Coordinator、NativeAnalysisArtifacts、WorkspaceDocumentView；未发现阻断下游接口的整合问题。N4完整功率覆盖及费用规则留给对应实现，不将初步就绪度当估算结果。
- 主工作区`Scripts/check.sh contracts` exit0；105共享Swift+Extension2、39Python、2项目/快照与28错误兼容交换、15真实native记录及6拒绝变异通过。日志：`Artifacts/NativeDelivery/n1-integrated-contracts.log`。正常/专用probe两端构建日志来自独立N1 worktree的`Artifacts/N1/`，主工作区构建在后续受影响整合复验。
- Mac27/Xcode27A266a：独立bundle`com.simunow.nativevalidation.mac`，CUA实际观察米制盒体/地板、旋转+放大后的画面变化、重置、无手势选择变绿与文字状态。三维坐标点选及native orbit拖动未观察到响应，保留未验收并交N2排查；不把按钮成功当手势成功。正常用户App及未保存文档未关闭。
- iPadPro13(M5)/iOS26.5、UDID1580DA0F-643D-423E-95A9-A766CB0493A8：simctl安装并启动独立bundle`com.simunow.nativevalidation.ios`，实际非AR渲染截图`Artifacts/NativeDelivery/n1-ipad-probe.png`。完整交互未验收；Device Hub的CUA观察连续timeout，未以截图冒充手势结果。
- 最低macOS14/iOS17实际运行时不可用。availability和deployment target编译通过只证明构建；V-N1-05/21以及平台相关项保持inProgress/notAvailable子项。真正窗体20次、读屏、两窗口、iPhone/iPad完整操作仍需后续验证。没有新增相机权限、安装数值引擎、关闭sandbox或对外发布。

N1主工作区`Scripts/check.sh mac`和`ios`均exit0/BUILD SUCCEEDED，日志`Artifacts/NativeDelivery/n1-integrated-{mac,ios}.log`。iPhone17Pro/iOS26.5独立bundle实际非AR渲染截图`Artifacts/NativeDelivery/n1-iphone-probe.png`，完整交互仍未验收。

N1补审459f20f已精确整合为7dbacf5（仅probe与交接）；专用两端构建通过，公开命中/输入计数及独立native相机ownership可观测。Mac新版本实际画面、模式切换已观察，画布点击计数与拖动仍未观察响应；未宣称原因已查明或修复通过。详见[整合审查](native-integration-review.md)。

## N2独立实施与实际运行初验（2026-10-03）

- 独立worktree `native-n2`，基点3ea5b56；最终124项共享Swift测试通过（N1的105项+19项N2），Extension2另列。正常Mac/iOS和独立Debug probe两端均BUILD SUCCEEDED；证据在该工作树`Artifacts/N2/`，根代理整合回归另记。
- 纯值审视：米制Z-up→Apple唯一转换、正尺寸重排、center pivot、六面UV/外向法线、真实墙片缺格、未知几何不替代；CameraState与选择不进入分析或undo。完整冻结build输入用于旧画面选择guard，方案/几何更新期间保留renderer相机而禁旧图点击。
- Mac27/Xcode27A266a独立bundle `com.simunow.nativevalidation.n2.mac`，产品`/private/tmp/SimuNow-N2-Probe/macOS/Build/Products/Debug/SimuNow.app`。CUA实际看见6×4×3房间、门窗空洞/轮廓、空调/座位符号及F-B 0.05m薄盒；点画布→B关注点业务选择，拖动改变视角且保留选择，画布滚轮缩放且外层表单不滚，俯视/聚焦/等轴重置均实际改变画面。
- 真实编辑回路：三维B关注点→编辑所选属性→X=4.0改4.5m→应用→重开表单确认4.5；撤销输入编辑→重开确认4.0。添加薄盒后聚焦相机保持，等轴重置恢复完整房间。强制二维分支显示同一XYZ、家具、门窗、输入风向和选择；此为现代系统主动能力分支验证，不能代替14/17运行。
- 两个真实WindowGroup窗口ID -1/-2已打开：第2窗初始独立输入/相机，左转有响应；Window菜单回第1窗后薄盒/二维模式/B选择保持。控制器相机独立性与20次suspend清理另由自动测试证明；这不是20次真实关窗的内存测量。
- 新Debug Host提供局部深色/最大字号开关，不改变用户系统偏好。Mac深色房间/轮廓/对象和文字已观察；macOS下最大字号环境没有明显放大，不能据此声称iOS大字号已通过。实际VoiceOver朗读、键盘全过程、横竖屏与移动端手势仍待验。
- iPadPro13(M5) UDID1580DA0F-643D-423E-95A9-A766CB0493A8、iPhone17Pro UDID6AD63A54-264B-4A6D-870A-590843DF62CE均iOS26.5：simctl安装启动独立bundle `com.simunow.nativevalidation.n2.ios`并取得完整房间渲染，截图`Artifacts/NativeDelivery/n2-{ipad,iphone}-probe.png`。默认布局下房间/门窗/设备可见，iPhone相机按钮分行可达；截图只证显示，不证触摸或文件操作。
- 未做：真实GPU帧耗时/峰值内存、20次系统窗口释放、最低14/17运行、真机和完整移动端交互。N2最小overlay仍逐段实体，N3须改合并mesh并量测满预算；不要把单测执行时间当帧率或实际房间精度。用户原Mac App/Xcode文档保持，未push/发布。

根代理精确cherry-pick 3c9f2e3为e2ea5f5。主工作区`Scripts/check.sh test/mac/ios`全部exit0，124共享Swift+Extension2与两端BUILD SUCCEEDED；日志`Artifacts/NativeDelivery/n2-integrated-{test,mac,ios}.log`。无Codable/schema改变，既有N1契约覆盖保持，未重复无关引擎测试。git diff --check通过；只合入24份N2归属文件，保留用户scheme/Pitch与原计划修改。按顺序进入N3，真实平台/性能限制继续台账追踪。

### N2真实窗口生命周期补验

- 最新独立Debug副本PID73097，仅操作`com.simunow.nativevalidation.n2.mac`。CUA真实新建并关闭20个WindowGroup窗口，ID从AppWindow-2连续至AppWindow-21，每次AX确认返回AppWindow-1；第5…20次在新窗口执行左转按钮后关闭。未观察到崩溃或窗口不可恢复。前4次只计开关，不计相机操作。
- `ps`驻留内存样本：两次开关后64640KiB，4次116144KiB，12次120016KiB，20次120512KiB。预热后4→20次增加4368KiB；该样本不是峰值、GPU内存或完整泄漏分析。结合控制器20次suspend释放自动测试，可确认此流程可反复使用；仍不宣称绝对无泄漏或无持续任务。
- 首个关闭后的CUA观察超时，下一次观察确认关闭成功。Metal记录期间一次ScreenCaptureKit捕获失败，记录结束后恢复；没有据此判断App崩溃，也没有终止用户原App或修改系统设置。
- 官方`RealityKit Trace`附加测试副本15秒，退出2：Frames/Metrics明确仅支持visionOS，不支持macOS。日志`Artifacts/NativeDelivery/n2-room-realitykit-record.log`。随后`Metal System Trace`20秒记录退出0；生成的整屏surface-swap表不是应用帧率，不能据此标记30fps通过。原始trace与导出移至独立临时目录`/private/tmp/SimuNow-N2-Profiling`，不提交或主动对外传输。
- Metal presented-handler导出288条全系统记录，其中测试PID73097为0条；该静态/后台采样没有提供测试App有效帧率。只筛选本次PID，不分析其他程序的记录。

## N3根代理实际交互审查（整合前）

2026-10-03，独立Debug bundle `com.simunow.nativevalidation.n3.mac`，生产`WorkspaceDocumentView`与真实Swift executor。输入为6×4×3 m synthetic F-A/F-B/F-C，几何和三方案嵌套ID一致；未使用预制结果或fake client。以下证据来自CUA实际操作，不能替代移动端、最低系统或物理准确度验收。

- F-A 0°首次明确采用genericCone v1（0.05 m、12°、32条、seed 1）；计算完成、checks passed、当前输入及加入项目状态可读。相交2、遮挡0、范围外1；三维可见有限锥形路径。
- 加入0.05 m薄盒后自动更新为相交1、遮挡1、范围外1，B详情指向`preview.occlusion.v1`和F-B薄盒；强制二维分支显示同源路径和裁剪端点。关系详情及规则/版本/run/hash可经独立面板滚动阅读。
- 同profile分别运行+30°及−30°候选：结果为0/0/3及1/0/2（相交/遮挡/范围外）。方案比较显示各自run，未制造舒适或节电排名。
- 原生导出`Artifacts/NativeDelivery/N3-QA-three-scenarios.simunow`，系统fileImporter重开成功；运行历史按需验证载入。磁盘包含四份真实input/result/manifest及三份配置；各result checks passed。基准无障碍run `967D6ADD-DB2B-42E3-AC96-8FFAD02B01DD`；薄盒基准`39E5C228-17B3-4DFE-94F5-2E20A199270D`；+30°`02B18F7C-5409-463E-A782-5D09012D9FC8`；−30°`E90ABF4F-BD6C-46A3-87D6-6EFB830FA9BD`。
- 配置输入NaN被明确拒绝，合法13°成功采用；工作区撤销恢复12°并触发更新。发现缺配置候选暴露`noScenario`及防抖期间沿用旧“计算完成”文字，已交N3修复，关闭需要修复后重新验证。
- 满预算executor与完整任务耗时分别记录。初次真实client端到端Debug p95约3.18 s、Release约1.48 s（不含请求准备/封装/持久化/250 ms防抖）；Release executor p95约35 ms。完整链路尚未达到200 ms，不能以纯executor或CPU测试冒充完整任务或GPU帧率。正在定位重复校验、哈希和同步侧文件追加成本。

- 随后退出该独立进程并从全新进程重开同一磁盘包；历史索引恢复四份文件，逐份载入基准/+30°/−30°后得到同run、同关系的三方案比较。这证明实际磁盘恢复而非原进程缓存。首次重开比较暂为空，需从历史手动载入；N5须完善消费者自动按需恢复，不无限预载历史数组。
- 独立iOS probe安装/启动于已有iOS26.5 iPad Pro13与iPhone17 Pro均退出0；启动动画结束后截图`Artifacts/NativeDelivery/n3-{ipad,iphone}-probe.png`显示真实工作区、待采用档案和房间。首次立即截图捕获过渡动画，未用作正常显示证据。DeviceHub的CUA连接再次5秒超时，未通过其他输入技术替代；移动端采用档案、手势、文件与分享仍未验收。

此时N3仍未整合；N4/N5尚未实施。移动端操作、最终来源分享及外部同ID文档替换需继续验收。
- 20次循环后首窗画布实际再次选中B关注点→删除→明确确认删除对象及引用，AX中B及其采样点消失，旧选择文字清除；撤销后B及其采样点恢复。该删除/撤销操作只在独立synthetic副本进行。

### N3最终状态文字复验

- 使用重新构建且不同bundle的`com.simunow.nativevalidation.n3.final.mac`真实工作区：F-A明确采用档案后计算完成；切+30°未采用候选仅显示待采用入口，旧“计算完成”及内部noScenario均不再显示。返回F-A时防抖阶段显示待更新；改13°完成后撤销回12°，观察到当前方法检查阶段，再完成为同当前输入2/0/1关系。旧终态已按当前请求身份隔离。
- 没有用这次状态复验替代取消/FakeClock自动测试；无新移动端或GPU性能结论。独立副本未覆盖原用户App。

## N3主工作区整合回归（2026-10-03）

根代理精确cherry-pick `f93730f`为`40718df`，56份N3源码/契约/交接文件。主工作区`Scripts/check.sh contracts/mac/ios`全部exit0；165共享Swift+Extension2、39Python、2项目/快照与28错误兼容交换、native17真实Swift记录+10拒绝变异通过，生成无漂移，两端BUILD SUCCEEDED。日志`Artifacts/NativeDelivery/n3-integrated-{contracts,mac,ios}.log`。本轮并行构建/契约只判功能回归，不拿竞争下计时当隔离性能。

完整差异审视包括纯碰撞/目标、后台mesh、当前stage/hash/取消、配置冻结、全项目Integrity、共享App client、公开strict codec及JSON/缓存安全优化；关键发现已修复并验证。N3运行/性能细节见[N3交接](N3-implementation.md)，92项台账按实际自动/手动证据更新。根主工作区计划修改与用户Pitch/scheme保留，30份用户材料哈希逐一未变；`git diff --check`通过。没有push或正式发布。

按授权顺序，N3代码整合审视已完成；剩余平台/性能及同ID外部替换风险继续N5交叉验收，下一类别N4包含所有估算/比较Should任务。

## N4实施中审查（尚未整合）

native_n4基于40718df在独立worktree实施全部01…05。根早审记录实际请求窗口缺项、能力/热输入/电价区间、比较背景与决策变量、外项目manifest、重复runID及passed结果载荷一致性问题；代理正在修复并执行最终contracts/mac/ios。已有178项草稿测试通过属于中间版本，不能替代最终SHA验证；生产Mac最新构建已由代理报告通过，最终日志待交接。

既有N2独立测试窗口的只读AX查询本轮亦返回5秒timeout，原生UI服务暂未提供新操作证据。不会使用AppleScript/CGEvent绕过；N4独立探针做好后有限复验，截图渲染、模拟器启动及真实系统按钮/文件操作继续分别记录。

全Plans链接检查：57份Markdown、232个相对链接、无缺失；92个验收ID唯一。计数为本轮检查时的文件集合，后续新增交接文件后重新检查。

## 目标调整与最终交叉审查启动（2026-10-03）

最新目标为N1～N4；不启动N5或PDF实现。N4仍完整执行全部任务。已开始补修已有完成事件的后台严格校验、封装任务取消与返回后会话generation核对、同projectID独立文档实例标识。修复尚未验证，不能记pass。N4独立iPad26.5启动画面已取得并实际查看，显示房间3D及估算入口；截图未操作计算按钮，不能替代估算卡片/触摸/文件操作验收。


## N1～N4最终主工作区回归（2026-10-03）

N4代理提交713e06e精确整合为c502e81，随后根代理修复已实现功能的跨阶段边界。取消/迟到封装、同UUID独立文档实例、最新binding与附件变化、缓存数学依据、重复序号及撤销事务新增10项回归；最终冻结源码的201项共享Swift均通过。当前授权范围为N1～N4全部任务，N5/PDF/ComparisonRecord/消费者分享与发行暂不实施。

| 检查 | 最终结果 | 证据 |
|---|---|---|
| `Scripts/check.sh contracts` | exit0 | 201共享Swift、2扩展、39Python、23份真实native记录、17拒绝变异、2跨语言项目/快照、28兼容/错误案例；`Artifacts/NativeDelivery/n4-final-review-contracts.log` |
| `Scripts/check.sh mac` | exit0 / BUILD SUCCEEDED | `Artifacts/NativeDelivery/n4-final-review-mac.log` |
| `Scripts/check.sh ios` | exit0 / BUILD SUCCEEDED | `Artifacts/NativeDelivery/n4-final-review-ios.log`；generic Simulator最低target编译，不代表最低系统运行通过 |
| 缓存/重复序号专项 | 2项通过 | `n4-final-cache-and-sequence-v2.log`，16.120秒；最终全测亦包含这些用例 |
| 用户文件保护 | 核对35份；交接时33份一致、2份外部更新 | 自动回归结束时35份均一致；交接时PitchDeck.pptx与style-guide.json更新，根未写入/纳入，保留新材料；其余33份与基线一致 |

现有锁定`Backend/.venv`，没有安装依赖。初次沙盒因嵌套SwiftPM sandbox/Xcode服务权限失败，获得自动批准的必要开发工具权限后重跑；没有关闭App sandbox。首轮201项回归有缓存fixture及构建中新旧object混用失败；修正fixture为真实v1积分载荷，源码冻结后专项与全测通过，没有放宽生产数学/缓存门槛。失败日志保留，不用代理191项代替最终201项证据。

电脑操作服务getState在约10.972秒后超时并重置；此前getApp亦未恢复。N4移动端截图只证明房间及入口显示，估算卡片、文件操作、深浅色/大字号/VoiceOver和GPU/App峰值没有新增验收证据。最低macOS14/iOS17运行时不可用。完整清单及继续验收步骤见[最终审查](N1-N4-final-review.md)、[逐项台账](native-acceptance-status.md)。未push或正式发布。

## N5/N6 本轮代码与 Linux 检查（2026-10-03）

用户新增授权 N5/N6，分支 `paco-development`、基线 `eda5d5c`。完整任务状态与 Apple 待验脚本见 [本轮交接](N5-N6-implementation.md)，新增协议见 [固定证据 v1](../../Protocols/consumer-evidence-v1.md)。旧 N1～N4 验证段落为历史证据，不代表本轮新增 SwiftUI/PDF/RoomPlan 分支已通过构建。

| 检查 | 结果 | 证据/边界 |
|---|---|---|
| `Scripts/check_portable_native.sh` | pass | Swift 6.0.3；17 项真实 Core/Simulation/Reporting 与纯 Workspace 值层测试；临时 Apple swift-crypto SHA-256 shim，无生产依赖改动 |
| Python 完整 unittest | pass | 锁定 pydantic/jsonschema；44 项，其中 5 项新解析/坏输入/预算测试 |
| 消费者真实 wire/schema | pass | 8 份真实 Swift 输出，17 个未来版本/额外字段/坏引用/时区/单位反例；匿名 exportHash 和校准原父数据复核 |
| 领域/native/消费者/worker schema 漂移 | pass | 旧 native 生成器排除独立 ConsumerEvidence DTO，保持既有 v1 schema 完全不变 |
| Swift 6 全源语法解析 | pass | 不解析 Apple SDK 类型、不能替代编译 |
| Xcode 工程生成/资源检查 | pass（静态） | 幂等，schemes 与基线字节一致；原创 PNG/JSON/隐私 plist 结构检查；Apple asset/string 编译未验 |
| `Scripts/check.sh test` | notAvailable | Linux 缺 SwiftUI；4 项新增文档/相机/事务平台回归未运行，旧整包回归未重跑 |
| `Scripts/check.sh mac` / `ios` | notAvailable | xcodebuild 不存在；没有本轮双端构建成功 |
| unsigned archive | notAvailable | 脚本主动拒绝无 Xcode；未产出可安装/签名包 |
| PDF页面/系统分享/RoomPlan/VoiceOver/试用 | notAvailable | Linux 无 Apple UI/扫描/读屏，须执行交接脚本后逐项保存真实证据 |

日志与真实合成 wire、CPU 8/16/32 方格 benchmark 在忽略的 `Artifacts/N5-N6/`。网格只记录合成守恒/散度/数组估算与单次 Debug CPU 时间，不作为真机预算、内存峰值或真实空间场验证。Swift/Python 全部通过后仍不将 N5 标发布就绪，不升级 N6 为通用物理模型。
