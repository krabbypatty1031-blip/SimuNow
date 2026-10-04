# 计算编排层

Python worker 把同一份 `ProjectDraft` 转成 EnergyPlus IDF 与 OpenFOAM case，编排求解，做质量门、座位采样、舒适和代表日电费。**不在 App 启动时下载或安装引擎。**

当前已接入：

| 命令 | 作用 |
|---|---|
| `doctor` | 探测本机 EnergyPlus 25.2.0 与 OpenFOAM v2512（`linux/arm64`，`buoyantBoussinesqSimpleFoam`）是否配置好 |
| `run-l1` | 代表日能耗：草稿 → IDF → EnergyPlus → 冷量 / 电功率 / 窗热 / 墙热 |
| `run-l2` | 代表工况气流：草稿 + **当前** L1 边界 → OpenFOAM → 五道质量门 → 座位 / 切片 / 流线 |
| `stub-task` | 不跑引擎的协议夹具，供任务通道测试 |

L0 / L3 **未配置**。`doctor` 在引擎目录缺失或版本不对时返回 `not_configured` 和修复提示，不会偷偷下载，也不会把未配置写成已算过。

## 检查与安装

无需先装引擎即可查 worker 是否能启动：

```bash
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
```

要跑真实 L1 / L2，先装一次引擎（二进制不进 Git），再把根目录指给 worker：

```bash
# 需要本机 Docker daemon 已启动；脚本锁定 Apple Silicon
test/engines/install_engines.sh
export SIMUNOW_ENGINES_ROOT="$PWD/test/engines"
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
```

`doctor` 应报告 L1 / L2 为 `configured`。Mac App 在「计算准备」里选同一个文件夹。iOS 不运行本 worker。

## 这一层做什么、不做什么

- **做：** IDF / case 转换、求解编排、质量门（含进口面导热）、座位最近单元采样、ISO 7730 附录 D、代表日电费、可行性比例。
- **不做：** UI、在启动时安装 EnergyPlus / OpenFOAM、把一天结果写成全年核证、质量失败时填写座位温度 0、把 L0 / L3 包装成 CFD。

只有哈希匹配的当前 L1 才把窗热、墙热写入 L2 边界；缺 L1 或 L1 已过期时保持草稿声明通量 / `zeroGradient`，不编造天气热流。

Mac 独立执行器与 iOS 远程任务客户端遵守同一套 JSON 协议（`Protocols/Schemas/`）。引擎只在 Mac Debug 本机 exec；Release 沙盒路径未交付。

更细的阶段状态见 [Plans/Delivery/status.md](../Plans/Delivery/status.md)。
