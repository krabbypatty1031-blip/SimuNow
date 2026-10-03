# P1-01 固定环境与复现

查询与本机检查日期：2026-10-03。**P1-01 已完成：strict doctor exit 0 / ready，容器与双引擎最小启动全部真实验证**（验证记录见 `Plans/Delivery/verification.md` P1-01 收尾节，ADR-018）。环境检查成功不等于物理验证成功；P1-02 基准尚未开始。

## 唯一主路线

Mac arm64 上运行 Python worker；现有 Colima + Docker 提供原生 Linux arm64 的 OpenFOAM 容器；EnergyPlus 在 Mac arm64 原生执行。目标是 CLI 研发环境，尚未接入 App Process/helper，未改 sandbox。

| 项目 | 固定目标 | 选择依据与验证边界 |
|---|---|---|
| 宿主 | macOS 14+ / arm64 | 当前实际 macOS 27.0.1；此 profile 不接受 x86 模拟执行 |
| Python | 3.13.16 / Backend/.venv | 独立环境与锁定依赖；2026-10-03 由 3.13.7 重钉（ADR-012，补丁级差异） |
| VM 工具 | Colima 0.10.3、Lima 2.1.4、Docker CLI 29.6.2；context colima | 版本实测匹配；daemon linux/arm64，server 29.5.2 为 VM 内置（client 匹配目标即可） |
| OpenFOAM | **OpenCFD / openfoam.com v2506**，linux/arm64 | 固定 digest 镜像已拉取；`version_command` 为 `buoyantSimpleFoam`（该镜像不含 foamVersion，版本/发行方从求解器横幅解析） |
| EnergyPlus | **26.1.0 / build 6f2e40d102**，官方 Darwin macOS13 arm64 tar.gz | SHA-256 校验通过；已在 macOS 27 真实执行 `--version` 匹配 |

manifest 唯一文件为 [src/simunow_worker/runtime/manifest.json](../src/simunow_worker/runtime/manifest.json)，随 Python package 分发；结构见 [manifest schema](../../Protocols/Schemas/runtime-manifest.schema.json)。团队目标不随 doctor 发现值变化。本机报告与临时日志放忽略的 `Artifacts/P1-01/`，不得复制机器路径或凭据到 manifest。

已比较：OpenFOAM 原生 Mac 源码编译会增加工具链维护；x86 Linux 引入模拟执行；另建 VM/远程节点没有现存可连接环境。本轮选复用 Colima 的 arm64 镜像。官方 2412、2506 与更新版本存在，本轮冻结可核实 arm64 镜像身份的 2506，不自动跟随新发布。EnergyPlus 26.2.0 已于 2026-09-30 发布；本轮选择 26.1.0 建立首个固定基线。Linux EnergyPlus 需要另管安装/镜像，Mac 原生官方资产足够明确且减少本轮安装环节。任何升级都改 manifest、记录 ADR 并重验执行/后续基准。

## 本地运行时（RuntimeLocal）

所有工具与重数据位于 `Backend/RuntimeLocal/`（gitignore）：CLI 二进制、LIMA_HOME（VM、guest 镜像、容器层）、DOCKER_CONFIG、EnergyPlus 目录。使用：

```bash
source Backend/RuntimeLocal/env.sh   # 设置 LIMA_HOME/DOCKER_CONFIG/PATH/SIMUNOW_ENERGYPLUS_EXECUTABLE
colima status                        # VM 应 Running（aarch64, vz, 4 CPU, 6 GiB）
PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor --strict --timeout 15
```

VM 为研发初始配置 4 核/6 GiB/20 GiB 稀疏盘（非物理最低要求，P1-05 实测）。colima 的小体量 profile（socket、ssh_config、模板）固定位于 `~/.colima`。**完整清理**：`colima stop` 后删除 `Backend/RuntimeLocal` 与 `~/.colima` 即可。

候选稳态求解器 `buoyantSimpleFoam`：v2506 官方源码索引说明其用于带浮力、湍流和传热的稳态流；具体热物性、辐射、湍流、近壁面策略及适用范围由 P1-02 基准决定。选择候选不代表室内射流精度已证实。自然对流基准之后仍需非等温送风射流基准。

## 官方来源与固定身份

以下均为 2026-10-02 查询的官方来源；未下载引擎或镜像层。

- [OpenCFD v2506 发行](https://www.openfoam.com/news/main-news/openfoam-v2506)、[发行历史](https://www.openfoam.com/download/release-history)：发行身份与固定版本。
- [OpenCFD 镜像说明](https://hub.docker.com/r/opencfd/openfoam-dev)、[2506 tags](https://hub.docker.com/r/opencfd/openfoam-dev/tags?name=2506)、[官方容器仓库](https://develop.openfoam.com/packaging/containers/-/blob/main/docker/README)：Ubuntu LTS 基础镜像，含运行程序、源码与构建工具，**不含 tutorials**。
- [Docker Registry 2506 index](https://registry-1.docker.io/v2/opencfd/openfoam-dev/manifests/2506)：通过公开只读 bearer token 请求 OCI index 与 arm64 manifest，再计算响应 SHA-256；本地证据在 `Artifacts/P1-01/source-metadata.json`。index：`sha256:2e66fd9e77048af7f1c36c739a60a740fbdff4c2f9f4f29429f1a16834f3960f`；选择 arm64 子 manifest：`sha256:f1a4b6a78ff41bbbedb901078e0abcdee94076933cadace44915ecd0282c89c1`。公开元数据记录压缩镜像层合计 340,320,682 字节，实际解压空间和性能尚未测量。
- [v2506 源码索引](https://api.openfoam.com/2506/files.html)、[buoyantSimpleFoam 文档](https://doc.openfoam.com/2306/tools/processing/solvers/rtm/heat-transfer/buoyantSimpleFoam/)：候选求解器依据，后者是较早版本说明；以 2506 实际源码/基准为准。
- [EnergyPlus 26.1.0 发行](https://github.com/NatLabRockies/EnergyPlus/releases/tag/v26.1.0)、[官方 API 元数据](https://api.github.com/repos/NatLabRockies/EnergyPlus/releases/tags/v26.1.0)：非 prerelease；Darwin macOS13 arm64 包 209,850,883 字节，官方资产 digest 为 `sha256:7f2ec425e67f5d71c668e4504db1b10d91dc4d8cb802e9a8ee70c4f02a46d379`。这是发行端校验值，尚未下载验证文件或安装。
- [Colima 官方仓库](https://github.com/abiosoft/colima)：Apple Silicon、Docker runtime 和独立 Linux VM 路线依据。
- [Docker run 官方说明](https://docs.docker.com/reference/cli/docker/container/run/)：`--pull=never` 防止 doctor 隐式下载。

## 本机实际盘点

| 项目 | 2026-10-02 实际结果 |
|---|---|
| OS / CPU / 物理内存 | macOS 27.0（sw_vers build 26A428）、arm64、34,359,738,368 字节 = 32 GiB |
| Python / 项目独立环境 | 3.13.7；Backend/.venv 已创建并安装全部锁定依赖，pip check 另见验证记录 |
| Docker / Colima / Lima | CLI 29.6.2 / 0.10.3 / 2.1.4 已发现；Colima 未运行；docker info 不可连接 |
| Linux VM / daemon 执行架构与内存 | 未知；limactl list 未发现实例；不能把 Mac arm64 当作 daemon 实测架构 |
| 镜像库存 | 未知，daemon 不可连接；注册表镜像身份不是本机安装证据 |
| 原生 OpenFOAM / EnergyPlus | PATH 与列出的常见安装目录未发现；所选 EnergyPlus binary 未安装，OpenFOAM 目标探测受 daemon 阻断 |
| Podman / Multipass | PATH 未安装；其他未配置外部环境仍为未知 |
| 远程计算 | 本 profile 未配置远程 adapter；未检查 SSH/凭据，不能推断外部节点不存在 |

常见目录仅查 `/Applications`、`/opt`、`/usr/local`、Homebrew opt 顶层的引擎/VM 名称；未搜索私人文件。初次沙盒检查无法读取内存/socket；允许的只读系统检查确认内存 32 GiB、daemon 不可连接。受限环境运行 doctor 会如实报告权限失败/null，与不受限终端的 unreachable 分开。

物理内存不是 VM 分配内存，也不是求解最低内存。manifest `memory.minimum_bytes: null`，依据为尚无算例测量；P1-05 再测粗/中网格内存与可行规模。不在本轮提供性能、时间或网格规模结论。

## 检查与本地配置

从项目根执行：

```bash
python3 --version  # 应为 3.13.16（ADR-012）
python3 -m venv Backend/.venv
Backend/.venv/bin/python -m pip install -r Backend/requirements-dev.lock
Scripts/check.sh runtime
Scripts/check_runtime.sh --strict
PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor --timeout 5
```

安装后用环境变量指定 EnergyPlus **真实 arm64 binary**，或加入 PATH；设置值属于本地配置，不提交。相对路径按当前 CLI 工作目录解释，建议从项目根运行。doctor 不回显路径。

```bash
source Backend/RuntimeLocal/env.sh   # 或手动 export SIMUNOW_ENERGYPLUS_EXECUTABLE='./Backend/RuntimeLocal/EnergyPlus/energyplus'
PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor --strict --timeout 15
```

该 RuntimeLocal 已按 ADR-018 承载全部工具与引擎下载，已加入忽略规则。不允许 shell wrapper 冒充 Mach-O 原生 binary。版本命令必须精确匹配版本与 build。OpenFOAM 使用固定 context + digest，不接受动态镜像覆盖；换环境必须显式传 `--manifest <JSON>` 并满足支持的 profile/固定身份验证。

doctor 只执行有限版本/状态命令；daemon 可用才 inspect 本地 digest，身份/架构吻合才在无 mount、无网络、只读、无额外 capability 的短命容器中执行 `uname -m`、`buoyantSimpleFoam -help` 与求解器版本横幅（该 v2506 镜像不含 `foamVersion`，版本与发行方从求解器横幅解析），分别验证实际执行架构、版本和最小启动。环境脚本目标 `/usr/lib/openfoam/openfoam2506/etc/bashrc` 已在固定镜像中执行确认。stdout 仅 JSON；默认退出 0 表示报告生成成功，严格模式 blocked 退出 2。详见 [doctor 契约](../../Protocols/doctor-v1.md)。

后续 case/weather/output 以项目根或项目包为基准，manifest 的 `runs/<run-id>/openfoam`、`weather/<weather-file>.epw`、`runs/<run-id>/` 为 P1-03/04 的布局约定，目前没有目录生成、挂载或求解实现。引擎路径仅 Backend adapter 读取，不进入 SimuCore/iOS。真实运行身份/哈希由 P3 建立。

## 完成门槛（已于 2026-10-03 达成）

1. ~~以现有 Colima 0.10.3 / Lima 2.1.4 配置或启动原生 arm64 Linux VM~~——已启动（vz，4 核/6 GiB/20 GiB 稀疏盘，研发初始配置；guest 镜像下载到 LIMA_HOME）。
2. ~~拉取固定 arm64 OpenFOAM digest~~——已拉取，digest 与 manifest 一致。
3. ~~下载官方 EnergyPlus 26.1.0 Darwin arm64 tar.gz 并校验 SHA-256 解压配置~~——已完成，`energyplus --version` 真实执行匹配。
4. ~~运行严格 doctor 并保存真实证据~~——`doctor --strict --timeout 15` exit 0 / ready（`Artifacts/P1-01/doctor-strict.json`）。

P1-02 从固定 2506 来源获取候选公开基准及原始对比数据（镜像无 tutorials，需独立固定来源），先浮力基准再非等温室内射流；保留物理适用范围、误差和守恒/收敛证据。最小启动证据不能替代任何基准。P1-03 再接输入→case→网格→求解→采样；P1-04 再固定天气/设备/代表日输入。
