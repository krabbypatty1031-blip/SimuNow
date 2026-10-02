# P3 执行计划：任务链路、输入哈希与 L0 代表日能耗（2026-10-03，development 分支）

展开 `Plans/Phases/P3-orchestration-energy.md`。本机无 Colima/Docker/EnergyPlus（doctor 实测 blocked），**L1 EnergyPlus 与 L2 OpenFOAM 在本环境保持 not_configured**；本计划实现完整任务框架并以真实 L0 稳态热平衡打通 App→worker→结果闭环。L0 是集总平均估算，UI 全程标注"L0 平均估算"，不产生逐点结论（硬约束 5）。L1 adapter 的接入条件记录于"遗留条件"。

## 用户操作与页面状态

- 工作区"计算任务"页：当前项目各方案的运行列表（run ID 短码、fidelity、状态、质量、新鲜度、开始时间）、进度/日志展开、取消按钮、失败原因与日志保留。
- 方案行内显示最近一次 L0 结果摘要（代表性指标 + "L0 平均估算"标签）；修改方案任意物理输入后，旧结果立即标记"待重算"（input hash 不等 → stale，不删除）。
- 提交前置：`inputPreparation` 校验通过；不满足时按钮不可用并跳转到校验列表。
- 异常：worker 缺失/版本不符 → 明确错误与修复路径（指向 doctor）；运行失败 → 状态 failed，保留 stderr 尾部与事件文件；取消 → cancelled，幂等（重复取消不报错）；旧 run 晚完成 → 只写入自己的 run 目录，绝不覆盖当前方案。

## 协议与数据

### RunInput（`Protocols/run-input-v1.md`，新增）

`{protocol:"run-input/1", runID, scenarioID, inputHash, fidelity:"l0", snapshot:<ScenarioInputSnapshot>, settings:{seed?...}}`。快照即 P2-01 不可变快照；evaluation（费用）参与哈希但在 L0 结果中只用于费用估算。

### 输入哈希

- 算法：`JSONValue.text()`（键排序的规范序列化）→ UTF-8 → SHA-256。Swift `InputHash` 与 Python `models.hashing` 双实现；contracts 增加两端对同一快照哈希一致的真实交换用例。
- 排除项：无——快照本身已排除显示状态；evaluation 是否参与哈希的决定：**参与**（电价变化影响费用结果），后续若引入纯视图字段再设排除清单。

### 事件流（`Protocols/run-events-v1.md`，新增）

worker stdout 仅 JSONL：`{protocol:"run-event/1", runID, sequence, timestamp, eventType, stage?, payload}`；eventType：accepted/progress/log/quality/completed/failed/cancelled。客户端校验 runID 匹配、sequence 单调、未知 eventType 拒绝；stderr 捕获为诊断日志。schema：`Protocols/Schemas/run-event.schema.json`、`run-result.schema.json`。

### RunResult（L0）

`{protocol:"run-result/1", identity, fidelity:"l0", metrics:[{name,value|missing,unit,aggregation,method,fidelity,assumptions}], quality:{state,checks:[...]}, assumptions:[...]}`。指标示例：`averageRoomTemperature`（°C，代表日运行时段平均）、`coolingLoadPeak`（W）、`dailyCoolingEnergy`（kWh 热）、`estimatedElectricEnergy`（kWh 电，标"等效 COP 估算"）、`capacityAdequate`（bool/insufficient_data）、`dailyCost`（缺失则无报价/电价）。任何无法计算项为 missing + 原因，不为 0。

### L0 物理口径（Backend `adapters/l0/steady_state.py`）

逐时刻（30 min 步长，代表日）稳态热平衡：
`Q_net = Σ U·A·(T_out−T_set) + ρ·c·V̇_vent·(T_out−T_set) + Q_solar − Q_internal`，冷负荷 `Q_cool = max(Q_net, 0)`（`T_set` 为控制设定；`Q_solar = SHGC·A_win·I`，日照强度 I 无天气文件时取显式假设并列入 assumptions；有 weather 引用但文件缺失 → 该指标 missing）。
- 电耗 = 冷量 / effectiveCOP；effectiveCOP 取设备 cop 参数（preset/manufacturer 来源），明确标注"等效模型，理想负荷口径"。
- 容量检查：peak 负荷 vs 设备制冷量 → adequate/undersized/insufficient_data。
- 平均室温：容量充足时 = 设定值；不足时按 deficit 与总热容导出的稳态偏移估算并标注。不做逐点、不做降温时间。
- 校验：输入校验复用 ProjectValidator（Python 侧），另查本 adapter `InputRequirements`（代表日、天气、围护、通风、控制时间表全天覆盖）。

## 模块与文件

| 文件 | 责任 |
|---|---|
| `Backend/src/simunow_worker/jobs/{__init__,runner,events}.py` | run 命令：读 RunInput、写 events.jsonl、原子写 result.json、取消标记文件轮询、异常→failed 事件 |
| `Backend/src/simunow_worker/adapters/l0/steady_state.py` | L0 计算，纯 stdlib |
| `Backend/src/simunow_worker/models/hashing.py` | 规范序列化 SHA-256 |
| `Backend/tests/test_l0.py`、`test_runner.py` | 能量口径、守恒/单调、取消幂等、乱序拒绝 |
| `SimuCore/Project/InputHash.swift` | 快照哈希（Swift 侧） |
| `SimuSimulation/RunProtocols.swift` | RunEvent/RunResult Codable + 序列校验解析器（跨平台，无 Process） |
| `SimuSimulation/LocalSimulationClient.swift` | Mac-only（`#if os(macOS)`）：Process 执行 worker、JSONL 流、进程树取消、run 目录管理 |
| `SimuWorkspace/Runs/RunStore.swift`、`RunsView.swift` | 运行列表、进度、结果摘要、新鲜度 |
| `SimuWorkspace/Editing/ResultPanel.swift` | 方案行内 L0 摘要（带保真度标签） |

worker 路径：Mac 端默认 `Backend/.venv/bin/python`（开发仓库内运行）；部署打包是 P7 ADR 范围。doctor 增加 l0 状态：L0 为纯 Python，环境满足即 `verified_available`（真实执行一次自检计算），engines.l1/l2/l3 保持 not_configured。

## 实施顺序与验收

1. hashing 双实现 + 契约用例 → 2. L0 计算 + 单测 → 3. runner/events + 单测 → 4. Swift RunProtocols 解析 + 单测 → 5. LocalSimulationClient（Mac）→ 6. Runs UI + 新鲜度 → 7. doctor l0 → 8. 验收。
- 验收命令：`check.sh all`；真实端到端：Mac App 从模板建项目 → 补全未知项 → 提交 L0 → 看到进度与真实指标 → 改设定温度 → 旧结果 stale → 再跑 → 两 run 各自保留。记录 run ID 与日志到 verification.md。
- 异常测试：乱序/截断/错 run 事件、取消幂等、worker 缺失、失败保留证据（test_runner + Swift 解析测试）。

## 遗留条件（不标记完成）

- L1 EnergyPlus adapter：需安装 EnergyPlus 26.1.0 并验证启动；设备曲线/天气文件来源。
- L2 OpenFOAM adapter：需 Colima VM + 固定镜像 + P1-02 基准。
- sandbox 内 Process/打包权限：P7 部署 ADR；当前仅开发环境（DEBUG 构建）验证。
