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

## ADR-006：P2 编辑不提供撤销（已接受）

日期：2026-10-03。
背景：P2-03g 要求先决定撤销范围，未实现却显示撤销会违反「无空按钮」。
选择：本阶段只编辑内存模型，不提供撤销栈；关闭未保存即丢失。
影响：P2-04 保存后以文件为真相；若以后要撤销，另开 ADR。
验证：`RoomEditorForm` 无撤销按钮。

## ADR-007：项目包为目录而非 zip（已接受）

日期：2026-10-03。
背景：P2-04 要求锁定 `*.simunow` 目录包或 zip 等价物。
选择：目录包 `Name.simunow/project.json`。先写 `FileManager.temporaryDirectory` 再替换目标，失败时保留旧 JSON。
影响：Mac 用 NSSavePanel/NSOpenPanel；iOS 用 folder/json 文件选择器。包路径只留在内存，不写入 project.json。P3 再在包内加 runs 快照。
验证：`PackageTests` 关闭重开与失败替换；工作区「打开 / 保存」绑定 `ProjectPackage`。

## ADR-008：沙盒内包 worker、用户只选引擎（已接受）

日期：2026-10-03。
背景：P3 要在 App 里提交真实 L1，但不能默认关闭 sandbox，也不能把开发者 Desktop 路径写进项目。
选择：Mac 把 `simunow_worker` 与 `test/p1` 三个 IDF 脚本打进 Resources/WorkerTree，运行时拷到 Application Support；用户用书签选一次 `test/engines`。iOS 保持 `UnconfiguredL1TaskClient`。不在本阶段做 helper。
影响：本机闭环只在 Mac；EnergyPlus 二进制仍由用户提供，不进 Git。`cs.disable-library-validation` 仅用于加载用户引擎。
验证：`WorkerStagingTests`；沙盒 App 手测办公室 L1 `succeeded`；entitlement 中 sandbox 仍为 true。

## ADR-009：L2 能量门禁计入实测进口面导热（已接受）

日期：2026-10-03。
背景：P4-02 钉版办公室弱射流（带速 0.1 m/s）求解收敛、监测稳定、质量守恒，但能量收支差 23.4%。诊断：fixedValue 进口面在热分层天花板下从近壁单元导热吸热，钉版 run 实测 −305.9 W；P1 大流量（1.2 m/s）下同一机制仅 ~−7 W（能量误差 0.41%），此前可忽略。
备选：(a) 放宽能量门禁——否，门禁是硬约束；(b) 改房间几何让热分层碰不到进口带——否，为过门禁改物理属造假；(c) 把进口面导热实测并计入收支。
选择：(c)。`foam_io` 解析 polyMesh + `writeCellCentres` 的 C 场，`quality.inlet_conduction_w` 逐进口面算 ρcp·(ν/Pr)·A·snGrad，预算 `q_extracted = h_out − h_in − q_inlet_cond`；层流假设被显式守卫（非层流拒绝估算，不猜 0）。计入后能量误差 0.19%，门禁保持 5%。
影响：`test/p1/{run_room,quality,sample_seats,foam_io}.py` 随 P4-02 进库（run-l2 依赖）；弱射流房间整体偏冷约 2.3 K 属该供应模型的真实后果，座位结果随 quality 披露，不包装为实测。湍流模型启用后需补 alphat 边界项再复算。
验证：`test/p1/test_quality.py`（合成 case 手算 −51.0087 W + 2026-10-03 真实数字回归：计入过 / 不计 23% 挂）；钉版 `test_l2_runner` 质量 passed、`quality.json` `terms_w.q_inlet_cond=-305.9`。

## ADR-010：舒适自实现 ISO 7730 附录 D，缺输入 omitted 带原因（已接受）

日期：2026-10-03。
背景：P4-04 要求座位级 PMV/PPD。草稿 schema 无任何舒适输入（无 clo/met/RH/MRT）；`pythermalcomfort` 未安装且按仓库规则不自动引入运行时依赖。
备选：(a) 引入 `pythermalcomfort`——否，新增依赖且沙盒 worker 打包更重；(b) 只做「不可评价」占位——否，输入齐全的调用方（P5+ 草稿假设）应有真实计算；(c) 自实现标准闭式方程。
选择：(c)。`models/comfort.py` 逐行移植 ISO 7730 附录 D 规范性程序（58.15 W/m²·met、分段 fcl、平均迭代 eps 1.5e-4、条件出汗项 0.42(mw−58.15)、hc 两分支取大）；适用域守卫（ta 10–30、tr 10–40、v 0–1、clo 0–2、met 0.8–4、pa ≤ 2700 Pa、PMV ±2）超范围抛 `NotEvaluable`，不猜值。锚点：附录 D 同算法的已发布输出（met 1.4 / clo 0.5 / RH 50：vr 0.22 → PMV 0.17 / PPD 5.6；vr 0.1 → 0.41 / 8.5，逐位复现）与标准 Table 2 / 图 1（PPD(0)=5%、(±0.5)=10%、(±1)=26%）。var 取座位实测风速（久坐无明显肢体运动，不做 met>1 的 Vag 附加）。
影响：`comfortInputs`（mrtC/rhPct/clo/met）为 `evaluate_l2` 上下文新键，runner 暂不传（无来源）→ 指标 `seat_pmv_min/max`、`seat_ppd_max` omitted + `reason` 列出缺失项；契约 metrics 行加可选 `reason`、座位行加可选 `pmv`/`ppd`（schema + Swift + 透传同步）；部分座位超适用域时聚合只覆盖可评座位并在 `reason` 披露排除口径。P5 若给草稿加舒适假设，runner 补传该键即可。
验证：`Backend/tests/test_comfort.py`（算法锚点、Table 2、单调性、六项守卫 + pa/PMV 域、缺/部分/超域座位、evaluate_l2 三态）；钉版 run 重生成 `Fixtures/task/result-l2.json`（座位值与旧 fixture 逐位一致 + 三条舒适 omitted 带 reason）；Python 70 + Swift 94 全绿；mac/ios BUILD SUCCEEDED。

## ADR-011：App 内 L2 走 staged 树与 test/engines 引擎路径，docker 可达性运行时自证（已接受）

日期：2026-10-03。
背景：P4 Goal 要求 Mac 改一个空间参数后提交代表工况 L2。App 沙盒内跑 OpenFOAM 的现实约束：仓库 `test/engines/openfoam.sh` 是 docker 包装（镜像 `simunow/openfoam:2512`），沙盒 App 访问 `/var/run/docker.sock` 与全局 docker CLI 未必可用。
备选：(a) 沙盒内直装 OpenFOAM——版本锁定与打包成本高，P1 验证后再议；(b) 全局关闭 sandbox——违反部署基线；(c) staged 树 + 文件探测 isConfigured，docker 可达性交给运行时，失败即 failed 不编造。
选择：(c)。staged 树扩展为九个 P1 脚本（L1 三件 + L2 六件：`run_room`/`write_openfoam_room`/`quality`/`sample_seats`/`foam_io`/`field_slice`）；`stageEngines` 落位 `runtime/test/engines`（与 `run_room.py` 硬路径 `repo/test/engines/openfoam.sh` 一致）并拷贝 `openfoam.sh`（源缺失时仅 L1 可用）；`LocalProcessL2Client`（macOS）以 `SIMUNOW_ENGINES_ROOT` 指 staged 引擎目录、`workerCommand="run-l2"`、超时 900 s；iOS 保持 `UnconfiguredL2TaskClient`。沙盒内 docker 不可达时 run 失败、座位/舒适指标 omitted，不降级为估算。
影响：`enginesURL(in:)` 语义从 `runtime/engines` 改为 `runtime/test/engines`（L1 probe 仍按 enginesRoot 下 `EnergyPlus/energyplus` 相对解析，行为不变）；`Scripts/generate_project.py` Stage WorkerTree 同步九脚本；App 内首跑 L2 的沙盒 docker 可达性待手测记录，未验证前不宣称 App 内闭环。
验证：`WorkerStagingTests`（六 L2 脚本 staged、engines 落位 test/engines）；`L2ClientTests`（未配置拒绝、wrapper 探测、field-slice 读取/缺文件 nil）；`Backend/tests/test_l2_staged.py` 以 subprocess 重建 staged 树全链路跑 `run-l2`（succeeded + quality passed + field-slice.json 落位，17.7 s）；Python 76 + Swift 113 全绿。

**实施补录（2026-10-03 14:35，P4 手测发现后修复）**：手测选择 `test/engines` 后 App 仍报「未配置：运行时须含 worker，引擎目录须含 EnergyPlus/energyplus」，且 staged 树缺 `openfoam.sh`。根因：`6a2c301` 起的 presence probe 用 `isExecutableFile`（底层 `access(X_OK)`），而 App Sandbox 对 staged 容器路径与用户选定引擎目录一律拒绝 X_OK（终端 `test -x` 同路径为真；sandbox-exec 复现：read 全放行下 X_OK 仍拒）——昨日 P3 手测成功是旧 build 无此 probe，非沙盒语义变化。修复：`LocalEngineProbe.hasExecuteBit`（stat 读 POSIX x 位；stat 只需读权限，且跟随 symlink——staged `energyplus → energyplus-25.2.0` 布局适用），`isConfigured`、`stageEngines` 的 destBinary 跳过与 wrapper 拷贝条件、`LocalProcessL2Client.probeIsConfigured` 四处统一改用；`LocalProcessClient` 的 python3 候选初筛保留 X_OK（系统路径在沙盒白名单内，`canStartInterpreter` 实测兜底，昨日 L1 成功已验证该路径）。引擎能否真跑仍是 run 的证据，probe 不代言。验证：`LocalEngineTests` 新增 stat 语义回归锚点（x 位/无 x 位/symlink 解析/缺失路径、0o644 拒绝）两项；Swift 117 全绿；mac/ios BUILD SUCCEEDED；App 内重选 `test/engines` 的手测复验进行中。

**实施补录（2026-10-03 14:50，P4 手测第二发现：python3 解析）**：probe 修复后引擎状态行转绿（「已配置代表日 L1 与代表工况 L2」），但 App 内提交 L1 failed，run 证据 `stderr.log` 仅一行：`xcrun: error: cannot be used within an App Sandbox.`。根因：`/usr/bin/python3` 是 xcrun shim（沙盒内被 xcrun 主动拒绝），而候选列表里 homebrew/CLT/Xcode 的真 python3 被 X_OK 探测跳过（同前项沙盒 X_OK 语义），全败后兜底仍返回 xcrun shim，提交必死无证据。修复：`resolvePythonExecutable` 候选初筛改 `hasExecuteBit`（stat），候选列表加入 CLT（`/Library/Developer/CommandLineTools/usr/bin/python3`，`/Library` 在沙盒默认读白名单）与 Xcode 内置真路径，`canStartInterpreter` 实测兜底筛掉沙盒里起不来的候选（如 homebrew 用户域路径），全败返回 nil——诚实未配置而非配置一个提交必死的 shim；`pythonExecutable` 转 optional + `isUsable`（nonisolated，只读不可变存储），L1/L2 的 `isConfigured` 折入 `inner.isUsable`，`submit` 对 nil 解释器直接拒绝；未配置文案补「且需可用的 python3」。worker 兼容 3.9（`from __future__ import annotations`，P3-11 已以 `/usr/bin/python3` doctor 验证）；数字口径不受解释器版本影响（watts 由 EnergyPlus 本体产生）。验证：`WorkerStagingTests` 新增 nil 回归锚点（无可启动候选时必须返回 nil 而非 xcrun 兜底）；Swift 118 全绿；mac/ios BUILD SUCCEEDED；App 内 L1/L2 手测复验进行中。

**实施补录（2026-10-03 14:55，P4 手测第三发现：worker 侧同款 X_OK）**：python3 修复后 worker 真跑起来了（run 证据出现 `run-l1 start`、`l1-room.json`/`result.json` 落位），但 L1 仍 failed，`stderr.log` 报 `run-l1 failed: EnergyPlus not configured; no invented watts`。根因：`l1_runner._energyplus()` 的 `os.access(X_OK)` 与 ADR-011 第一项是同一沙盒语义坑——worker 本身跑在沙盒 App 的子进程里，对 staged 容器路径（`~/Library/Containers/.../runtime/test/engines/EnergyPlus/energyplus`，相对 symlink → `energyplus-25.2.0`）的 X_OK 同样被拒，于是「未配置」地诚实失败。修复（Python 侧三处统一改 `has_execute_bit`，stat `st_mode & 0o111`，跟随 symlink）：`models/task.py` 新增 helper（stat 只需读权限，沙盒容器内必给）；`l1_runner._energyplus`、`l2_runner._openfoam_wrapper`（staged `openfoam.sh`，同路径）、`__main__._probe_l1`（doctor 同口径）。doctor 与 Swift probe 同语义后，「终端 doctor configured + App 内未配置」这类分裂不再可能。验证：`test_task_protocol.py` 新增回归锚点（x 位真/无 x 位假/symlink 解析/缺失路径，chmod 0o755/0o644）；Python **80** 全绿（+1）；Swift 118 全绿；mac/ios BUILD SUCCEEDED（mac 重建使 staged WorkerTree 带上本修复）；App 内 L1 手测复验进行中。

**实施补录（2026-10-03 15:00，P4 手测第四发现：staged 引擎被 macOS quarantine）**：worker 侧 X_OK 修复后 L1 仍 failed，`stderr.log` 的 traceback 走到了真正 exec EnergyPlus：`PermissionError: [Errno 1] Operation not permitted`（execve EPERM，stat 已放行）。证据：系统日志（`/usr/bin/log show`）两次提交各记两条拒绝——`(Sandbox) Python deny(1) process-exec* .../energyplus-25.2.0` 与 `(Quarantine) exec ... denied since it was quarantined by SimuNow; and created without user consent, qtn-flags was 0x00000086`；sandbox-exec 对照实验：staged（带 quarantine）exec 复现 EPERM、源目录（无 quarantine）沙盒下 exec 成功（`EnergyPlus, Version 25.2.0`）；`spctl` 证实 NREL Developer ID 签名未公证（Unnotarized）。根因：App 把引擎文件拷进自己容器时 macOS（Tahoe）对产物自动打 `com.apple.quarantine`（agent=SimuNow，"created without user consent"），沙盒内 exec/加载「quarantine + 未公证」二进制即被拒——终端跑源目录（从无 quarantine）所以 P1-04/P3 手测一直成功；清理主二进制后 dyld 又死于 `libintl.8.dylib`（444 只读拒删 xattr，`library load disallowed by system policy`），说明整树 7676 文件都带 quarantine。修复：`WorkerTreeStaging.stageEngines` 末尾新增 `stripQuarantineRecursively`（`stageEngines` 每次无条件重拷 wrapper、每次重拷都重打标记，故清除必须每次跑且覆盖已存在文件）：`getxattr` 先探测（绝大多数文件无标记，一次探测保持 7000+ 文件遍历廉价），带标记的常规文件 `removexattr`，444 只读文件先借 owner-write 位、清后恢复原权限；symlink 跳过（exec/dyld 评估 resolved target，target 已在遍历内）；失败抛 `quarantineNotStripped`（staging 失败比静默必死诚实）。现场修复：终端手清 staged 树（含 libintl.8.dylib 借写位删除）后 sandbox-exec 完整 exec `--version` 成功——run 而非 probe 是证据。验证：`WorkerStagingTests.stagingStripsQuarantineFromStagedEngineFiles`（真实 `setxattr` 打标记（借写位打、恢复 444，还原现场形态）→ re-stage（EnergyPlus 跳过重拷、wrapper 重拷两条路径都覆盖）→ 断言三文件无标记、444 权限恢复）；Swift **119** 全绿（+1）；mac/ios BUILD SUCCEEDED；App 内重启后 L1/L2 手测复验进行中。

**实施补录（2026-10-03 15:10，P4 手测第五发现：沙盒进程删不掉 quarantine，引擎改为就地用）**：带 strip 的新 build 启动即报「引擎文件 openfoam.sh 的隔离标记无法清除」——App 内对重拷的 wrapper（带新 quarantine、755 有写位）`removexattr` 仍 EPERM。证据：staged wrapper 带新打的 quarantine（`0086;...;SimuNow;`，权限 755，排除权限原因）；系统日志 10 分钟窗内**无任何 seatbelt deny 记录**——拒绝不是 profile 层，是内核对 quarantine xattr 的保护（Tahoe：沙盒 App 不能删除 quarantine，非沙盒终端进程可以；此前 strip 的「成功」只是对无标记文件的跳过——App 内 removexattr 从未真正删成过，手清全部由终端完成）。删除标记此路不通，改为**绕开标记**：引擎不再拷进容器（拷贝即打标），从用户选定目录（bookmark 已授权 read-write，无 App 写入即无标记）就地运行——`applyEnginesOnly` 的 `enginesRoot` 改传用户目录本身，`SIMUNOW_ENGINES_ROOT` 落到用户目录；`WorkerTreeStaging` 精简为仅 stage worker 与 P1 脚本（staged 全是 Python 数据文件，quarantine 无碍读取与解释执行），`stageWorker` 幂等移除旧 build 拷入的 staged 引擎树（含 400 MB EnergyPlus），`stageEngines`/`enginesURL`/strip 与 `quarantineNotStripped` 全部移除；`run_room.py` 的 `OPENFOAM_SH` 改为 `SIMUNOW_ENGINES_ROOT` 覆盖、无 env 时保留 repo 路径（CLI 语义不变），缺 wrapper 报错带上解析后的路径。L1/L2 的 probe（stat 执行位）与 worker（`_energyplus`/`_resolve_weather`/`_openfoam_wrapper`）本就按 `SIMUNOW_ENGINES_ROOT` 相对解析，无需改动。沙盒能否 exec 用户选定目录的二进制属 profile 层，仅手测可证——C/D 步为检查点；若被拒需另立 ADR（临时例外或独立 helper）。验证：`WorkerStagingTests.stageWorkerDropsLegacyStagedEngines`（预置 legacy staged 引擎 → stageWorker → 断言被移除且 worker 树仍落位）替代原三个引擎 staging 测试；`L2ClientTests` 三处随 `enginesURL` 移除改直构目录；Python `test_l2_staged` 以 staged 引擎目录传 env 全链路真跑（17.7 s，succeeded + quality passed）验证 env 覆盖；Swift **117** 全绿、Python **80** 全绿、mac/ios BUILD SUCCEEDED；App 内 L1/L2 手测复验进行中。

**实施补录（2026-10-03 15:15，P4 手测第六发现：用户选定文件读写不等于 process-exec）**：就地用引擎后 L1 仍 failed，run 证据走到真正 exec 用户目录二进制：`PermissionError: [Errno 1] Operation not permitted: .../test/engines/EnergyPlus/energyplus`（路径已是用户选定目录，不是容器副本）。系统日志只有一条：`(Sandbox) Python deny(1) process-exec* .../EnergyPlus-25.2.0-.../energyplus-25.2.0`——**无 quarantine 记录**。根因：`com.apple.security.files.user-selected.read-write` 只授权读写，不授权 exec；App Sandbox 默认 `(deny process-exec*)`，用户目录里的 NREL EnergyPlus（Developer ID、未公证）被拒。这正是第五段预留的 profile 层检查点，也是 P3-11「hardened runtime 允许启动用户选择的 EnergyPlus」未完成的那一项（当时只加了 `disable-library-validation`，那管的是加载未签名 dylib，不是 exec）。备选：(a) 全局关 sandbox——违反部署基线；(b) 现在做签名 helper——P7 路径，本轮手测来不及；(c) `temporary-exception.sbpl` 放宽 exec/fork，文件沙盒保持。选择 (c)，并预放 L2 所需的 docker unix socket 例外（`/var/run/docker.sock` 绝对路径 + `~/.docker/run/docker.sock` 家目录相对路径，不写死开发者 Desktop）。另：沙盒子进程 PATH 是 `/usr/bin:/bin:/usr/sbin:/sbin`，Docker Desktop 的 `docker` 在 `/usr/local/bin`，`LocalProcessClient.workerEnvironment` 把 `/usr/local/bin` 与 `/opt/homebrew/bin` 前缀进 PATH，避免下一层 `docker: command not found`。`l1_runner` 对 `OSError` 诚实 failed（IDF 留作证据，不编造瓦特）。生产路径仍是 platform-and-release.md 的签名 helper，本例外是手测闭环用的临时桥。验证：`macEntitlementsKeepSandboxAndAllowProcessExec`（sandbox 仍为 true 且含 process-exec 例外）；`workerEnvironmentPutsDockerOnMinimalSandboxPath`；Swift **119** 全绿（+2）；Python **80** 全绿；mac/ios BUILD SUCCEEDED；App 内须重启使新 entitlements 生效，L1/L2 手测复验进行中。

**实施补录（2026-10-03 15:16，P4 手测第七发现：sbpl 例外导致启动即崩）**：带 `temporary-exception.sbpl` 的新 build 在 Xcode 启动即停在 `libsystem_secinit` / `libsecinit_appsandbox` 的 `EXC_BREAKPOINT`——沙盒 profile 编译失败，进程在进入 `main` 前被 secinit 主动打断。根因：(c) 在本机 macOS 上不是合法可合并的 sandbox 片段，开发签名 App 会被拒绝；Continue 无效。备选回到第六段 (a)(b)：全局关 sandbox 违反「不以关 sandbox 为默认修复」；签名 helper 仍是 P7。选择：**只在 Debug 配置关掉文件沙盒**（`SimuNowMacDebug.entitlements` 不含 `app-sandbox`，保留 `disable-library-validation` 以便 EnergyPlus 加载 NREL 签名 dylib）；Release 仍用 `SimuNowMac.entitlements`（sandbox=true，去掉非法 sbpl）。`generate_project.py` 给 SimuNowMac Debug 覆盖 `CODE_SIGN_ENTITLEMENTS`。这是手测闭环的配置例外，不是把关 sandbox 写成产品默认。验证：`macReleaseEntitlementsKeepSandbox`（Release sandbox true 且无 sbpl）；`macDebugEntitlementsSkipSandboxForEngineExec`；Swift **120** 全绿；mac/ios BUILD SUCCEEDED。用户须在 Xcode 点 Stop 再 ⌘R（当前会话停在 secinit 断点）。

**实施补录（2026-10-03 15:30，P4 手测 C–E 闭环）**：Debug 配置下办公室模板走通代表日 L1（3099.335 / 1033.112 W）、默认口 L2（质量 passed，座位 24.43–24.73 °C，切片 23.35–25.21 °C）、改送风口 **高度** z0/z1 2.48–2.66→2.10–2.28 m 后再 L2（24.21–24.50 °C）、两列对比（共用色标 23.0–25.2 °C，freshness 与 quality 独立，PMV 均 omitted + reason）。几何注意：P1 case 把送风口展成整墙条带（`l2_room.py` assumptions），沿墙平移 s0/s1 或换墙 xMin→yMin **不改** `blockMeshDict`，只有 z0/z1（或宽度缩放速度、房间尺寸）改进口带——手测 E 因此改高度而不是平移。任务页 `lastResult` 单槽：提交 L2 后代表日瓦数显示未知，磁盘 L1 run 仍在。Release 沙盒产品闭环仍未成立，生产 exec 仍是签名 helper。

## ADR-012：人员热源以「每人显热」为 L1/L2 对账基准，先披露后对齐（已接受）

日期：2026-10-03（当日以 EnergyPlus 分项输出修正根因）。
背景：单变量实测（`room_p1.json` 唯一改 `n_people` 8→3，两个 IDF 逐行 diff 仅差 People 数，真实 EnergyPlus）发现每人「冷量足迹」≈177.6 W：`q_cool_w` 6334.87→5446.86（−888.02 W），`p_elec_w` 同步 −296.00 W（=−888.02/3），两边 `zone_t` 均 26.0。分项实测（追加 Output:Variable 重跑）：每人 = 显冷 133.3 + 潜冷 44.3 W，其中直接对应人员得热仅 70 W（显 57.0 + 潜 13.0，恰好等于 Activity 表 70 W 全额，守恒闭合）；剩余 ~107.6 W/人是送风为凝结人员湿负荷过冷到更低露点的间接冷量。根因：`write_idf.py` 的 `People` 行把 70 W/人当**活动代谢率**（显热分率由引擎自动定，实测 ≈0.81，IDF 中的 0.3 字面未作为 SHF 生效），而 `L2BoundaryMapping` 把模板 `occupantSensibleW=70` **全额当显热体积源**——office 8 人时 L1 人员显热 456 W vs L2 560 W，L2 温度场虚增 104 W（13 W/人）。违反 AGENTS.md「人员与设备热源在 L1/L2 中同口径」红线的精神：数字分开有注释，但显热份额未真正对齐。
备选：(a) 仅在口径对照表披露、不改数字——否，L2 座位温度场带 392 W 虚增热源，位置级结论失真；(b) 改 L1 让 70 W 变纯显热（SHF=1.0）——否，抹掉人员产湿使 L1 漏算真实潜热/除湿负荷；(c) 把 `occupantSensibleW` 语义定为「每人显热」，L1 的 People 对象按同额显热 + 潜热单列口径写入，L2 保持显热体积源，潜热只进 L1 的 `q_cool` 账。
选择：(c)。实施时点：P4-06 三方案对比之前完成 `write_idf` 人员显热份额与模板值对齐，并重钉 `Fixtures` 与 P3 手测数字；实施前对照表披露该错位，L2 座位结果按「人员源含口径余量」披露。对账规则：跨 L1/L2 的「人员热」对比只以**显热**为基准；`q_cool` 含新风与人员潜热（除湿），不可与 L2 显热收支直接比大小；PMV 所需 RH 由草稿舒适假设单独供给（缺则 omitted，ADR-010），L2 场不解湿度。
影响：`q_cool_w` 语义不变（总冷量含潜热）；对齐后 L2 座位温度将小幅下移（人员源 560→456 W，8 人办公室虚增 104 W），座位结论随之更新，旧 run 标 stale 不复用；`test_l1_schedule`/`L2BoundaryTests` 同步改口径断言。
验证：2026-10-03 单变量实测（8/3 人两 run 目录 `test/outputs/p1_l1/20261003T053325Z`、`20261003T053649Z`；IDF diff 仅 People 数；CSV 日总冷量差 73.54 MJ 与均值口径一致）＋分项实测（追加 Output:Variable 重跑：显冷差 133.3、潜冷差 44.3、People 显 57.0/潜 13.0 W 每人，合计 70 守恒闭合）；对齐实施时补 `write_idf` People 显热断言与双端契约测试。

**实施补录（2026-10-03，对齐已完成）**：模板 `occupantSensibleW` 70→57（office/classroom JSON + `BundledTemplateJSON` 两处 + `project-v2-office.json` fixture 第 5 处（用户报漏后补钉，`test_project_model` 加断言锁值），语义=每人显热，实测拆分）；`write_idf.py` 新增 `OCCUPANT_LATENT_W=13`（显式单列，只进 L1 `q_cool`），People 行 activity=显+潜=70 **逐位不变**（SHF 字面 0.3 保留并加 IDF 注释「引擎自行拆分」），L1 IDF 与 P3 手测数字无需重跑；L2 人员显热源 560→456 W（虚增 104 W 消除），钉版重跑 `Fixtures/task/{result,field-slice}-l2.json`（固定 UUID aaaa…/cccc…，inputHash `aa0e6da1…`）：座位温度 **24.43–24.73 °C**（对齐前 25.08–25.39 为 70 W/人全额显热错位口径）、切片 23.35–25.21 °C（24×24 全有效）；断言更新 `test_l1_schedule`（activity 跟随显+潜的敏感性断言 + office activity 70 逐位基线）、`test_boundary`/`test_l2_room`（456 W / 57 W）、`L2BoundaryTests`/`L2RoomMappingTests`/`ContractTests`（57 口径）。Python 78 + Swift 125 全绿；mac/ios BUILD SUCCEEDED。**第 6 处补钉（2026-10-03 14:08，验收发现后修复）**：`test/p1/fixtures/room_p1.json` 的 `gains.people_w` 70→57（同口径漏改；对齐后该字面按「每人显热」语义使 L1 activity 漂到 83 W、CLI 复现 `q_cool_w=6571.94`，P1-04 历史证据 6334.87 不可复现）。补钉后实测：L1 CLI `q_cool_w=6334.873993885751` 与 2026-10-02 P1-04 记录**小数点后 12 位一致**（run `test/outputs/p1_l1/20261003T060835Z`）；L2 CLI 同夹具重跑质量全过（`quality.pass=true`，座位 16.96–18.68 °C 与 57 W/人口径单变量实验逐位一致，run `test/outputs/p1_room/20261003T060935Z`）；Python 79 项全绿。

## ADR-013：成人办公舒适默认写入草稿，缺项仍不编造 PMV（已接受）

日期：2026-10-03。
背景：P4 舒适算法已通，但草稿无 `mrtC/rhPct/clo/met`，App 内 PMV 恒为 omitted。P5 建议卡若继续「舒适不可评价」，比赛故事讲不完。产品范围写明儿童人群需独立评价，不能把成人办公模型偷偷套到教室当实测。
备选：(a) 继续缺输入 omitted——建议卡无舒适；(b) 用座位气温冒充完整舒适且不披露——违反 ADR-010；(c) 模板写入成人办公假设，source=`assumed`，reference 写来源，教室额外披露「儿童未单独评价」。
选择：(c)。默认值锁定：

| 量 | 值 | 单位 | 依据 |
|---|---|---|---|
| clo | 0.5 | clo | ISO 7730 夏季轻薄办公着装量级 |
| met | 1.2 | met | ISO 7730 久坐办公 70 W/m²（1 met = 58.15 W/m² → 1.2 met） |
| rhPct | 50 | % | 比赛演示湿度假设，不是房间湿度场 |
| mrtC | 26 | °C | 假设等于区设定，**不是辐射求解**；不取 L2 气温反填 |

`l2_runner` 从草稿 `occupancy.comfort` 组装 `comfortInputs`。用户可改；清空任一项 → 指标 omitted + reason，不填 0。教室模板用同一组成人默认，并在假设列表写「儿童人群未单独评价」。
影响：schema / Swift / Python / 办公室与教室模板同步可选 `occupancy.comfort`。钉版 L2 fixture 在传入舒适假设后 PMV 将有值，须重钉或加独立夹具，不得把旧 omitted fixture 说成有 PMV。
验证：`ComfortAssumptionTests`（office 四键 source=assumed；教室「儿童人群未单独评价」；v2 无 comfort 仍解码）；`Backend.tests.test_comfort.ComfortInputsFromDraftTests`（完整四键评 PMV；缺 clo omitted + reason）；`DecisionVariableTests`（改设定保留候选并警示「不是有效比较」）。`Fixtures/task/result-l2.json` 仍 omitted，未改钉版数字。

## ADR-014：代表日电费用演示电价，改造费待报价（已接受）

日期：2026-10-03。
背景：P5 要比较运行成本。没有真实电价来源，不能编造港币或回收期。全年情景不存在（`annual_kwh` 已永 omitted）。
备选：(a) 无电价就不算费——对比页缺运行费；(b) 编一个「市场电价」不写来源——违反费用红线；(c) 明确的演示假设，可编辑，必须带 source/reference。
选择：(c)。默认：`1.2 HKD/kWh`，source=`assumed`，reference=`比赛演示假设，非真实电价`。代表日电量 = `p_elec_w / 1000 × 占用小时`（办公室模板 08:00–18:00 → 10 h）；代表日电费 = 电量 × 单价。缺 `p_elec_w`、缺占用时段或电价 → 费用 omitted，不填 0。改造/设备报价无来源 → 「待报价」，不出回收期、不出全年费。改设定后的节电必须来自新的 L1 run，不得乘系数。
影响：`CostAssumptions` 进草稿或工作区状态，不写死 Desktop 路径；`CandidateRun` 冻结 pin 当时的 L1 电功率与代表日费用。
验证：P5-03 `CostAccountingTests` 与 `Backend.tests.test_costing`（1033.112 W × 10 h → 10.33112 kWh → 12.397 HKD；缺电价只省略电费；缺电功率电量与电费都 omitted；结果对象无有值的 `annual_kwh` / `payback_years`）。电价不进物理输入哈希，改价不把 L1 瓦数标成 stale。

## ADR-015：PDF 由证据包出数字，模型 API 只写叙述（已接受）

日期：2026-10-03。
背景：用户要求加模型 API，让模型整合生成 PDF。计划要求报告引用冻结 run、不从 View 重算、每条结论有 run ID/方法/假设。LLM 直接出带数字的 PDF 会编造瓦数、达标率和费用。
备选：(a) 纯 Swift PDFKit 表格，无模型——叙述弱；(b) 模型直接生成整份 PDF/HTML，数字也由模型写——不可复核；(c) 先由代码生成不可变 `ReportEvidence`，模型只填指定叙述槽，排版器只把证据包里的数字画进 PDF。
选择：(c)。

- **证据包**（Swift + Python + schema）：候选 run ID / inputHash / quality / 座位指标 / 达标比例 / 代表日电费 / 假设 / 建议卡结构化字段。数字只来自已有 L1/L2 结果，不经模型。
- **叙述器协议** `ReportNarrator`：输入整份证据 JSON，输出 `headline` / 各卡 `prose` / `caveats`。实现一：OpenAI 兼容 `POST {baseURL}/v1/chat/completions`。密钥只来自环境变量 `SIMUNOW_REPORT_API_KEY` 或钥匙串，不进仓库、不在启动时下载模型。
- **排版器**：Mac `PDFKit` 画证据表 + 叙述段落。叙述里出现的数字若不在证据包数值集合中，该段降级为「叙述未采用（含证据外数字）」，表格仍在。
- **API 未配置或失败**：仍导出证据-only PDF（表 + run ID + 假设）。演示不依赖外网。
- **拒绝**：模型重算指标；模型声称合规/全局最优/实测满意率；把 View 状态当报告源。

影响：P5-04 先做证据包与无模型 PDF，再接可选叙述器。P5-05 离线演示验收的是证据 PDF，不是 API 连通。具体供应商/baseURL 实现时写入本地配置，不写死公钥。
验证：P5-04 已测。`ReportEvidence` 数字等于候选 `seat_pass_ratio` 与代表日费用；无 `SIMUNOW_REPORT_API_KEY` 时 `narrate` 返回 nil 且 PDF 仍写出；夹具「节电 37%」整段被拒为「叙述未采用（含证据外数字）」。假密钥不出现在 PDF、project JSON 或叙述日志。见 `RecommendationTests`、`ReportEvidenceTests`、`NarratorGuardTests`、`Backend.tests.test_recommend`。

**实施补录（2026-10-03，ADR-019）**：导出路径改为 DeepSeek 生成可读正文；无密钥不再写证据-only PDF。证据包出数字与数字守卫仍有效，见 ADR-019。

## ADR-016：3D 视口选 RealityKit 方案 A（只读查看，已接受并落地）

日期：2026-10-03。
背景：用户要求调研 3D/更佳展示方式（信息以用户为核心）。查证现行 SDK（Xcode 27 / macOS 27 SDK）：`RealityView` 与 `RealityViewCameraContent.camera = .virtual` 的可用性是 **macOS 15 / iOS 18**，不是初稿写的 14/17。工程最低版本仍是 macOS 14 / iOS 17；旧系统走 Canvas `RoomWireframeView`。
备选：(a) 维持 Canvas 2D；(b) SceneKit；(c) Metal 直绘；(d) RealityKit。交互又分方案 A 只读查看、B 点选、C 三维拖柄。
选择：(d) + 方案 A。用户 2026-10-03 明确「先按照方案 A 来做」。不做点选、不做 3D 拖柄。架构落点：`SimuVisualization`；Canvas 保留为降级。显示红线不随渲染器变化：质量未通过不画彩色、invalid 格中性灰、稳态场不做时间动画、对比页共用 `SlicePalette` 与 yaw。座位名走 `UserFacingCopy`，不把 `z0` / `L1` 画回界面。
影响：三项 spike 结论——(1) 切片上色走 `SliceTextureBuilder` CGImage → `TextureResource(image:withName:options:)` + `UnlitMaterial(texture:)`，色=温度；(2) 不用系统 `.orbit` 控件，以免对比页共享 yaw 被各自相机拆开；`ViewportOrbit` 转房间根节点（yaw/pitch/zoom）；(3) Entity 非 Sendable，实体操作全部收在 `@MainActor` `RoomEntityBuilder`。沙盒无涉：系统框架、无 Process/exec。
验证：2026-10-03 落地。`Scripts/check.sh test`：SimuCoreTests 171 + SimuVisualizationTests 23。`Scripts/check.sh mac` / `ios` BUILD SUCCEEDED。钉版 1033.112 W / 10.33112 kWh / 12.397 HKD 与座位温度未改。App Debug 三维手测仍待用户点：拖转、捏合、有场才上色、对比两列同朝向。

**实施补录（2026-10-03，示意三维）**：用户要求模板里的空调、窗、人有可辨认的三维外形，且可随时增删，同时保留温度切片。显示层用 `RoomSchematicMeshes`（壁挂室内机、回风格栅、带框窗门、示意桌、椅+坐姿人偶）；网格尺寸是辨认约定，不改载荷/风量/采样点。办公室模板仍 `obstacles: []`（`omitted: furniture_boxes`），不编造桌子。检查器原有增删窗/门/家具/座位保留；补 `removeHVAC`。`RoomDisplayLayout.buildID` 含贴片与座位坐标，移动或删除会重建 RealityView。切片仍走质量门控 `SliceTextureBuilder`。验证：SimuCoreTests 172 + SimuVisualizationTests 28；`mac` / `ios` BUILD SUCCEEDED。钉版数字未改。仍无点选/三维拖柄。

## ADR-017：用户向界面第一轮只做呈现，3D 后置（已接受）

日期：2026-10-03。
背景：P5 链路已通，但四页与检查器直接展示 `L1`/`z0`/`inputHash`/`PMV`。需要先让非技术人员能对比方案。
选择：检查器保持总表、加折叠（房间 / 使用 / 空调）；视口只改图例、空状态、座位人话名；提交计算放到「用电与舒适」。点选、拖拽、补画门家具、RealityKit 3D 不进本轮。呈现集中在 `UserFacingCopy`，不改 schema、哈希、质量门。
影响：第一轮可按 [UX-user-facing-ui](../Phases/UX-user-facing-ui/UX-user-facing-ui.md) 实施。ADR-016 的 RealityKit spike 明确排在本轮完成之后，且必须复用同一套用户文案，不能把求解变量画回界面。
验证：2026-10-03 落地。`Scripts/check.sh test`：SimuCoreTests 170 + SimuVisualizationTests 11 全绿。`Scripts/check.sh mac` / `ios` BUILD SUCCEEDED。钉版 1033.112 W / 10.33112 kWh / 12.397 HKD 与座位温度未改。呈现层 `UserFacingCopy`；检查器默认房间/使用/空调；提交在「用电与舒适」；PDF 正文「对比说明」，哈希在「详细编号」。App Debug 手测仍待用户点一遍八条清单。3D 按 ADR-016 方案 A 另开工作包，本轮不做点选/拖柄。

## ADR-018：多窗合并投影——添加窗必须同时进入 L1 与 L2（已接受）

日期：2026-10-03。
背景：敏感性实测发现追加第二扇窗后 L1/L2/电费逐位不变。根因是四个投影（`l1_room` / `l2_room` / `boundary` / `p1_mapping`）用 `next(...)` 只取第一扇窗，用户「添加窗」的操作停在草稿层；另外 UI「应用开口」会把模板窗声明的 `heatFluxWm2` 静默抹成 nil。
备选：a) 保持单窗，UI 禁止添加窗；b) L2 case writer 支持逐窗 patch（多墙多带）；c) 投影层把全部窗合并进既有单窗结构。
选择：c。L1 窗面积取**全部窗求和**进单一东墙窗（IDF 结构不变）；L2 带通量取**全部窗 W 求和 ÷ 带面积**（总 W 守恒，单窗结果逐位不变）；`boundary` DTO 用面积加权平均通量；`p1_mapping` 顶层面积求和。Swift 侧 `applyOpening` 缺省**保留已存热通量**（编辑窗不再丢 80 W/m²），`addOpening` 给新窗默认 80 W/m²（`assumed`，同两模板）。
影响：单窗房间数值逐位不变（office 基线不漂移）；添加带通量窗 → 面积与 W 同时进两层 → 冷负荷、电费、座位温度都动；未声明通量的窗只进 L1（面积）不进 L2（0 W 是声明的零，不是编造）。简化仍在 assumptions 披露（多窗合一带/单东墙窗）。
验证：`Backend/tests` 新增多窗用例（L1 求和 / L2 总 W 守恒 / 无通量窗归零 / DTO 加权平均）；`RoomEditingTests` 新增保留热通量与显式写入两例。引擎实测见 `status.md` P5 后补条目。

## ADR-019：L2 逐窗 patch 取代整墙通长带（修订 ADR-018 L2 半边，已接受）

日期：2026-10-03。
背景：P4 敏感性实测发现 ADR-018 只解决「W 进不进」，没解决「进在哪」——L2 把全部窗合成一整墙通长热带，挪窗（xMax 墙 s 2.25→0.30）、换墙（xMax→yMax）后切片颜色逐位不变，用户改窗位置的操作停在草稿层。根因：case writer 面归 patch 只有 inlet/outlet/单窗/walls 四种，窗的 s 区间根本不进 blockMesh 切分。
备选：a) 维持合并带（ADR-018 现状，位置不敏感）；b) L2 case 逐窗 patch + 三向切分（xMax/yMin/yMax 各自 s0/s1 切 s 向，送/回/各窗 z0/z1 切 h 向）；c) UI 禁止改窗位置。
选择：b。三条口径写死在投影与 writer：
1. **同墙重叠窗合并成包围盒**，q = ΣW/A_bbox（W 守恒，非重叠窗各自进网格）；
2. **xMin 墙窗撞送/回风带 → ValueError**（inlet/outlet 与窗 patch 同面冲突不静默算 0）；
3. **legacy L1 单窗双形状逐位不变**（`window` 单块照旧，`windows[]` 才走新口径）。
影响：`frontAndBack` 并入 `walls`（patch 集合随窗数变化）；能量门 `q_window_w` 改 Σ 逐窗 q×A；钉版 `result-l2`/`field-slice-l2` 重钉（4 座位 24.43–24.73 / 23.348–25.207 → 8 座位 24.42–24.71 / 23.376–25.448，模板带舒适默认后 PMV 0.16–0.21 已评价）；energy 门 0.19%→0.38%，仍在 5% 门内。L1 半边（全部窗求和进单一东墙窗）**不动**，ADR-018 L1 部分保留。
验证（2026-10-03，`Artifacts/sensitivity/` 本地存证，三 run 均 succeeded/quality passed）：办公室重钉 mass 1.97e-6、energy 0.38%；挪窗（同 W 移 s）切片最热点 y=2.88→0.62；换墙（xMax→yMax）暖区跟到 yMax 墙 y=5.62。`Backend/tests` + `test/p1` 183 passed（含真跑引擎钉版复算）、Swift 184 passed、mac/iOS 编译过。红斑（网格/粘度阶梯）不在本 ADR，见 P4-07B（门禁为唯一裁判）。

## ADR-020：L2 有效粘度与网格停在 nu 0.003 + 24×20×18（P4-07B，已接受）

日期：2026-10-03。
背景：P4-07A 后窗几何进网格，但切片红斑弱——nu 0.006 是约 400 倍空气分子粘度的有效粘度，混合强，窗边局部暖区被搅匀；网格 16×12×14 也分辨不出窗边梯度。P4-07B 阶梯实验六档全过五门禁（`Artifacts/sensitivity/p4-07b/ladder.json` 本地存证）：nu{0.006,0.003,0.0015}×mesh{16×12×14,24×20×18}，无一档失败收敛；切片 max 全部落在窗面 0.12–0.19 m 内，且随 nu 降低从 25.45 升到 26.69 °C——红斑在物理上自然出现。
备选：a) 最低过门档 nu 0.0015；b) nu 0.003；c) 维持 nu 0.006。
选择：b + 网格 24×20×18。裁决依据：
1. **门禁为唯一裁判**：六档全过，无档被门禁排除；
2. **0.0015 不取的披露理由**：近/远窗座位温差在粗细网格下**变号**（16×12×14 为 −0.12 K、24×20×18 为 +0.00 K）——座位级结果网格敏感，钉版数字将挂在不稳健工况上；0.003 在两网格下同号一致（+0.08/+0.15 K）；
3. **红斑验收**：nu 0.003 + 24×20×18 切片 max 26.34 °C 贴窗 0.12 m（nu 0.006 时 25.45–25.91 °C），自动色标下窗边自然显红，无人工对比度；
4. **预算**：solve 61 s（全管线约 90 s），`l2_runner` 内部 600 s 与 App 900 s 外层均不动，余量约 10 倍。
影响：`l2_room.py` 默认 mesh/nu 改为 `_ladder(24/20/18)`、`_ladder(0.003)`（source `p4_07b_ladder`），assumptions 加两条（阶梯选中披露 + 有效粘度非分子粘度）；`test/p1/fixtures/room_p1.json` 同步；`test_room.py` kappa 复算改为从 room 读 nu（不再硬编码 0.006）；钉版 `result-l2`/`field-slice-l2` 再重钉（A 后 8 座位 24.42–24.71 °C / PMV 0.16–0.21 / 切片 23.376–25.448 → B 后 25.157–25.314 °C / PMV 0.29–0.32 / PPD 7.1% / 切片 23.826–26.124 °C）。nu 仍是湍流代有效粘度（laminar 求解器不变），assumptions 如实披露；坐高座位温差零点几度是座位离窗 ≥1.5 m 的真实物理，不是红斑弱的缺陷。
验证（2026-10-03）：六档阶梯全过五门禁且逐档记录（mass 3.7e-8–3.3e-6、energy 0.015%–1.12%）；`Backend/tests` + `test/p1` 183 passed（含真跑引擎钉版复算 576 格点）、Swift 184 passed、mac/iOS 编译过；App 通道重钉 run（`p4-07b/repin/`）state succeeded / quality passed；App 手测（SimuNowMac Debug）红斑紧贴窗框、远窗侧偏蓝、数字与钉版一致（`verification.md`「P4 App 手测」F 行）。

## ADR-020：对比说明按真实结果陈述 EnergyPlus/OpenFOAM、方案对比与全年电费（已接受）

日期：2026-10-03。
背景：用户要求 DeepSeek 报告（1）展示 EnergyPlus/OpenFOAM 计算结果及窗、室内平均温度、气流的影响；（2）对比方案一/方案二的优劣、能耗与全年电费；（3）给出建议；并把数据当作真实结果，不再另加免责说明。
备选：(a) 只改提示词、让模型自己乘 365——守卫会拒掉证据外数字；(b) 把 `annual_kwh` 写进 L1 结果——破坏代表日会计契约；(c) 在冻结 `EvidenceRun` 上增加窗/场/代表日×365 的报告层字段，提示词要求四节并禁止免责套话。
选择：(c)。

- 提示词源：`ReportWriterSkill.systemPrompt`；维护规范：`.cursor/skills/llm-report/SKILL.md`。
- 报告层全年用电/电费 = 代表日 × 365 占用日，半入规则与日值相同。L1 指标 `annual_kwh` 仍 omitted。
- 正文必须点名 EnergyPlus、OpenFOAM；附录印窗、室内均温、气流、全年电费；电价印数值，不印「比赛演示假设，非真实电价」。
- 改造仍无报价则写待报价，不出回收期。

影响：用户可见报告将代表日外推为全年费用；这是报告层口径，不是新的 EnergyPlus 年模拟。
验证：`annualTotalsScaleTheRepresentativeDay`（3770.8588 kWh / 4524.905）；证据包拷贝窗/均温/气流/年值；DeepSeek 请求 system 消息等于 `ReportWriterSkill.systemPrompt`；守卫放行证据内全年电费。

## ADR-021：对比报告改由 AI 整理——pairDiff 证据包 + 用户四节，删分类卡（已接受）

日期：2026-10-03。
背景：原对比报告靠代码分类的「说明卡」（RecommendationKind：explanation/operation/comfort/retrofit）拼装，用户改为让 AI 做报告整理：AI 输入是两个方案的 diff 及 diff 导致的结果，输出是用户中心的报告（方案总结 + 建议下一步），保持用电/舒适维度。
备选：(a) 只改提示词、让模型自己找 diff 数字——守卫会拒掉证据外数字；(b) diff 证据包 + 固定维度小节（代码减好 delta 进证据，AI 照抄叙事）；(c) 保留分类卡只换文案。
选择：(b)。裁决依据：
1. **门禁前置拦截**：无任何候选通过质量门时不调 AI（`isComparisonReportable`），不出报告；
2. **基准门转 AI 输入**：使用条件不同不再拦截导出，`basisMismatchReason` 如实写进证据，AI 必须向用户如实说明；
3. **建议只给方向**：第四节限可调项（窗户数量与位置、出风口位置与高度、设定温度、出风温度、出风速度与风量、人数与座位），不编预测数字；
4. **delta 先减后述**：`CandidateDiff`（Swift）/ `pair_diff`（Python）在代码里减好（second−first，half-up 两位，防 −0），AI 只照抄，`NarrationGuard` 放行 delta 与 inputChanges sentence 里的数字。

影响：删 `Recommendation.swift` 与分类器；`ReportEvidence.cards` → `pairDiff: CandidatePairDiff?`（firstName/secondName/inputChanges/resultDeltas/basisMismatchReason）；`citedRunIDs` 改 candidates+l1RunID；四节标题换为「你的两个方案 / 用电对比 / 座位舒适对比 / 建议下一步」；PDF 附录 cards 循环改「两个方案的差异」段；`WorkspaceView` 报告详情改 pairDiffSection；Python `recommend.py` 同步 pair_diff（覆盖面为该通道扁平字段子集，schema optional 允许）；schema required 里 "cards" → "pairDiff"；App 内数字表格保留，无密钥不写 PDF 维持 ADR-019。
验证（2026-10-03）：`Scripts/check.sh test` 187 全绿（含 pairDiff 断言：出风高度句、energy/comfort delta、basisMismatchReason nil、单方案 pairDiff nil、PDF「两个方案的差异」）；`mac` / `ios` BUILD SUCCEEDED；Python 测试见运行记录。

## 待决定

- P1：OpenFOAM 分支/版本/求解器/网格与湍流，EnergyPlus 版本与设备模型（运行时已钉，文档待收口）。
- P7：代理/远程/发布渠道。
- 方案 B/C（点选座位、三维拖柄）是否做：方案 A 已通后另议。

每条新增决策记录触发原因、备选、选择、影响、验证证据与日期。
