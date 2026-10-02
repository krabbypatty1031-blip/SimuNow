# 计算编排层

当前只有 Python 包边界和 `doctor` 能力查询，未接入任何数值引擎。

无需安装依赖即可检查：

```bash
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
```

下一步按 [P1](../Plans/Phases/P1-physics-spike.md) 与 [P3](../Plans/Phases/P3-orchestration-energy.md) 建立 `adapters/`、`jobs/`、`postprocessing/`、`quality/`。
依赖在实际接入阶段锁版本；不要在 App 启动时在线安装 Python、EnergyPlus 或 OpenFOAM。
macOS 独立执行器与 iOS 远程任务客户端遵守相同协议。当前 `doctor` 返回可用的诊断接口状态，不代表引擎可用。
