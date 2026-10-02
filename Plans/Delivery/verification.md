# 工程验证记录

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
