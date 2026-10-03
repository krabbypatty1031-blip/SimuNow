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

## P2 编辑套件 + P3 任务链路验收（2026-10-03，development 分支）

环境：Apple Silicon Mac（tanchai），macOS 27.0.1 arm64，16 GiB，Xcode 27.0 (27A266a)，Python 3.13.16（Backend/.venv，锁定依赖）。本轮覆盖提交 2ad08b2（P2 全套 + P3 基础）与其后的 P3 收尾（runner 接入 CLI、协议文档与 schema、Swift 运行协议、Mac 本地执行器、任务页 UI、doctor L0 自检）。

| 检查 | 结果 | 证据与范围 |
|---|---|---|
| `Scripts/check.sh contracts` | 退出 0 | Python 71 项（models 14 + doctor 27 + hashing 6 + L0 10 + runner 14）；生成漂移/schema 漂移检查；`contract_run.py` 对 2 份夹具做真实 `python -m simunow_worker run` 并逐行校验 run-event schema、result 过 run-result schema、输入过 run-input schema（跨文件 $ref 经 referencing registry 解析）；Swift 39+2 项；双向交换 2 项目/快照 + 28 错误案例 + 2 份 Swift 写出的 RunInput 由 Python 校验 schema 与哈希一致。日志 `Artifacts/P3/check-all-p3.log` |
| `Scripts/check.sh mac` / `ios` | BUILD SUCCEEDED ×2 | 关闭签名；iOS 为 generic Simulator。同日志 |
| `Scripts/check.sh runtime` | 退出 0 | doctor 27 项行为测试 + 本机真实诊断：engines.l0=verified_available（真实执行两次自检计算且结果一致），l1/l2/l3=not_configured，environment=blocked（本机无 Docker/Colima/EnergyPlus）。日志 `Artifacts/P3/check-runtime.log` |
| `Scripts/check_runtime.sh --strict` | 退出 2 | 环境受阻时严格门槛正确拒绝；日志 `Artifacts/P3/check-runtime-strict.log` |
| CLI 端到端真实运行 | 通过 | 夹具 office → RunInput（runID 44D203E6…，inputHash 4b87711d…）→ worker 退出 0：peak 371.2 W、日冷量 8.909 kWh、电耗 2.97 kWh（等效 COP）、容量充足、平均室温=设定 25°C、dailyCost 缺失并注明「不编造费用」、quality passed。产物 `Artifacts/P3/demo-run/` |
| runner 异常路径 | 通过（单测） | 哈希不符退出 3+failed 事件；协议/UUID/哈希格式/scenarioID 不一致退出 3 且无事件；快照非法退出 1 保留证据；开始前取消与运行中取消都得 cancelled；重复取消无害；adapter 异常写 stderr.log；stdout 纯 JSONL |
| Swift 事件解析 | 通过（单测） | 跨行分块、错 run/乱序/缺口/未知 eventType 拒绝、截断报错、未知可选字段容忍、空行容忍 |
| Mac 本地执行器 | 通过（真实进程集成测试） | posix_spawn SETSID 进程组；端到端完成（accepted→progress→quality→completed、序列连续、result 身份一致）；开始前取消得 cancelled；exit 3 无事件表面化为 workerCrashed(3)；哈希不符得 failed 终态且 result 留证 |
| RunStore | 通过（非 UI 测试） | 提交门控（inputPreparation 不过不提交）、完成加载 result、改输入即 stale、双 run 各自目录互不覆盖、磁盘恢复、无 result 的目录标记「已中断」、事件流截断报完整性错误、取消透传 |
| App 内发起运行（sandbox 下 GUI） | 未验证 | 子进程继承 sandbox，读取仓库路径预期被拒；打包桥接（helper/companion）是 P7 ADR。GUI 手动演示路径待用户本机执行 |
| iOS 实际启动/真机/最低系统 | 未验证 | 编译通过不等于运行验证 |
| L0 物理正确性 | 未标定 | 单测与夹具只验证计算接线与口径诚实；不是实测/基准对比 |

基线复核（本轮开头，提交 2ad08b2 原样）：contracts/mac/ios 全绿，Python 54 项、Swift 27 项、交换 2+28 通过（日志 `Artifacts/P3/baseline-*.log`），确认已完成的 P2/P3 基础真实可编译可测试。

App 内运行 worker 的开发配置（一次性，本机）：`defaults write com.simunow.mac simunow.worker.python "<仓库>/Backend/.venv/bin/python"` 与 `defaults write com.simunow.mac simunow.worker.src "<仓库>/Backend/src"`；run 目录位于 `~/Library/Application Support/SimuNow/Runs/...`（ADR-014）。

## P5 决策与基础报告验收（2026-10-03）

执行计划：`Plans/Execution/P5-decision-report-execution.md`（含范围裁减说明）。全部验证在 L0 口径下进行；舒适与年度费用按硬约束不提供。

| 检查 | 结果 | 证据与范围 |
|---|---|---|
| 有效 run 筛选 | 通过（单测） | completed+质量通过+未过期才参与；stale/质量失败/未完成/无运行分别排除并说明（ComparisonModelTests） |
| 同口径分组 | 通过（单测） | 修改室外温度的方案进入不同 basis 组，不互相排序 |
| 候选生成 | 通过（单测） | ±1 °C 设定候选保留实体 ID、新 scenarioID；设定未知不生成；风向/角度候选不生成（需 L2） |
| 建议卡 | 通过（单测） | 运行调整卡选最低电耗方案且含 run 短码与方法；容量卡报峰值与不足；舒适卡固定为「需 L2」状态；无有效 run 时只解释不推荐 |
| 报告构建 | 通过（单测） | ReportContent 含 runID/输入哈希/质量/假设/费用分层；缺失费用显示缺失原因不含 0；stale run 被排除（content 为 nil） |
| PDF 导出 | 通过（单测） | BasicReportExporter 产出 %PDF 有效文件（分页、非空、中文系统字体）；无有效内容时导出抛出 noEligibleContent |
| `Scripts/check.sh all` | 退出 0 | Python 71 项、Swift 49+2 项、契约运行与交换、macOS/iOS BUILD SUCCEEDED；日志 `Artifacts/P5-check-all.log` |
| App 内演示（生成候选→运行→对比→导出 PDF） | 未验证 | 需用户本机手动执行；sandbox 下 App 内 worker 执行仍待 P7 桥接 ADR |

## P1-01 收尾验收（2026-10-03，本机 tanchai，用户授权安装）

下载与安装全部位于 `Backend/RuntimeLocal/`（gitignore；清理：停 VM 后删除该目录与 ~/.colima）。VM 为研发初始配置 4 核/6 GiB/20 GiB 稀疏盘（非物理最低要求，P1-05 实测）。

| 步骤 | 结果 | 证据 |
|---|---|---|
| colima v0.10.3 / limactl 2.1.4 / docker 29.6.2 | 版本精确匹配 manifest | `colima version`、`limactl --version`、`docker --version`；limactl 对上游 SHA256SUMS 校验匹配（14c5b283…） |
| arm64 VM 启动 | 通过 | `limactl list`：colima Running，vz，aarch64，4 CPU/6 GiB；guest 镜像下载到 LIMA_HOME（RuntimeLocal/lima） |
| OpenFOAM 镜像 | 拉取成功 | digest `sha256:f1a4b6a7…` 与 manifest 一致（340 MB 压缩层，52 秒） |
| EnergyPlus 26.1.0 | 校验+真实启动 | SHA-256 `7f2ec425…` 匹配 manifest；209,850,883 字节；`energyplus --version` → `EnergyPlus, Version 26.1.0-6f2e40d102`，exit 0（macOS 27 原生 arm64） |
| `doctor --strict --timeout 15` | **exit 0，status=ready** | container verified_available（linux/arm64，server 29.5.2/client 29.6.2）；openfoam verified_available（RepoDigests 含固定身份、容器内 uname=aarch64、版本 2506 匹配、`-help`+横幅执行、清理 ok）；energyplus verified_available；blockers 为空。`Artifacts/P1-01/doctor-strict.json`，过 doctor-report schema |
| 非 strict doctor | exit 0 | `Artifacts/P1-01/doctor.json`，过 schema |
| `Scripts/check.sh all` | 退出 0 | Python 72、Swift 52+2、契约与双端构建；`Artifacts/P1-01/check-all-p1.log` |

执行中发现并修复的问题（如实记录）：
1. doctor inventory 版本正则不匹配 `colima version v0.10.3`（v 前缀处无 `\b` 边界）→ 修正为 `\bv?(\d+\.\d+\.\d+)\b` 并加回归测试。
2. OpenFOAM 探针以位置参数 `$1` 传 bashrc 路径：OpenFOAM 配置链对指向自身的 `$1` 递归 source（复现：`set -- <bashrc>; source <bashrc>` → ~11 秒挂起后 SIGSEGV）→ 改为脚本内嵌字面路径。
3. manifest `version_command=foamVersion`：该 v2506 镜像不含 `foamVersion`（`ls bin` 确认）→ 修正为从 `buoyantSimpleFoam` 横幅解析版本/发行方（manifest 与 runtime-manifest schema 同步，banner 实测含 `Version:  2506` 与 `Website:  www.openfoam.com`）。
4. 探针 5 秒默认超时过短（容器冷启动 ~12 秒）→ 验收用 `--timeout 15`。
5. colima 小体量 profile 固定位于 ~/.colima（COLIMA_HOME 实测不改变其位置）；重数据均在 RuntimeLocal，清理步骤见 env.sh 注释。

最小启动验证不是物理验证：P1-02 公开基准（浮力→非等温射流）尚未开始，镜像不含 tutorials，需独立固定来源。

## 应用启动验证（2026-10-03，本机 tanchai）

| 检查 | 结果 | 证据与范围 |
|---|---|---|
| Mac App 进程启动 | 通过 | 直接运行 Debug 产物（无签名构建）：进程存活 6 秒并响应正常终止信号；无崩溃日志。Debug 无签名构建不应用 sandbox 描述文件，日志有一条预期内的 sandbox_extension 提示。未做界面交互检查 |
| iOS App 模拟器启动 | 通过 | iPhone 17 模拟器（已安装运行时）启动 → install → launch 成功分配 PID（28271），5 秒后仍在运行，随后正常 terminate 并关闭模拟器。未做界面交互与真机验证；最低系统（iOS 17）实机仍未验证 |

## 只读 3D 几何预览（2026-10-03）

用户要求在建模阶段提供 3D 视图（ADR-017）。范围：纯几何只读预览，非编辑器、不含场数据。

| 检查 | 结果 | 证据与范围 |
|---|---|---|
| 布局数学 | 通过（3 项单测） | 房间/墙/门窗/家具/座位/采样点/风口箭头的域→Apple 坐标映射逐值断言；未知尺寸返回 nil 不猜值；相机轨道数学与距离；布局指纹稳定且随编辑变化（RoomPreviewLayoutTests） |
| SDK 可用性 | 编译通过（分级） | Xcode 27 实测 RealityView 为 macOS 15+：availability 分级，macOS 15+ 预览、更低系统回退说明、iOS 17 回退说明；最低部署版本不变（ADR-002 预期路径） |
| `Scripts/check.sh all` | 退出 0 | Python 71、Swift 52+2、契约与双端构建；日志 `Artifacts/3d-preview-check-all.log` |
| App 启动（含预览代码） | 通过 | Debug 进程存活 6 秒正常终止；预览为手动切换标签，默认俯视编辑不受影响 |
| 预览视觉效果/手势 | 未自动验证 | RealityKit 画面与拖转/缩放需用户本机切换「3D 预览」标签目验 |
