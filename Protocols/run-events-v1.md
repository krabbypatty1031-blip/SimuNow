# Run 事件流与结果 v1

P3 新增。worker 执行期间的进度/状态通道与最终产物。输入见 [run-input-v1.md](run-input-v1.md)。

- 事件协议标识：`run-event/1`；结果协议标识：`run-result/1`；camelCase；UTF-8。
- worker stdout **只承载 JSONL 事件**，每行一个完整事件；stderr 是诊断日志，不进入协议。事件同时 tee 到 `<runDir>/events.jsonl`。
- 实现：Python `simunow_worker/jobs/{events,runner}.py`（产生），Swift `SimuSimulation/RunProtocols.swift`（解析）。
- Schema：[Schemas/run-event.schema.json](Schemas/run-event.schema.json)、[Schemas/run-result.schema.json](Schemas/run-result.schema.json)。

## 事件

```json
{"protocol":"run-event/1","runID":"…","sequence":3,"timestamp":"2026-10-03T01:23:45.678Z","eventType":"progress","stage":"solving","payload":{"step":8,"totalSteps":48}}
```

| 字段 | 必需 | 约束 |
|---|---|---|
| protocol | 是 | 常量 `run-event/1` |
| runID | 是 | 每个事件都必须等于本次运行的 runID |
| sequence | 是 | 从 1 开始的连续整数，严格递增；缺口即截断 |
| timestamp | 是 | UTC ISO-8601，毫秒精度，`Z` 结尾 |
| eventType | 是 | `accepted` / `progress` / `log` / `quality` / `completed` / `failed` / `cancelled` |
| stage | 否 | 阶段标签（如 `solving`、`checking`）；残差类数值放 payload，不把残差当总进度 |
| payload | 否 | 事件负载，自由结构；未知可选字段向前兼容 |

一次运行以 `accepted` 开始，以且仅以 `completed` / `failed` / `cancelled` 之一结束。终态、质量状态、结果新鲜度是三条独立的轴。

## 客户端校验（拒绝规则）

- runID 与期望不符的事件：拒绝。
- sequence 不等于「上一个 + 1」：拒绝（乱序或截断）。
- 未知 eventType：拒绝。未知可选字段：容忍。
- 流末尾存在不完整行：视为截断，报错。
- 取消幂等：重复取消不改变状态；旧 run 晚完成只写自己的 run 目录，不覆盖当前方案。

## 结果（`<runDir>/result.json`）

原子写入（同目录临时文件 + rename）。结构：

```json
{
  "protocol": "run-result/1",
  "identity": {"runID": "…", "scenarioID": "…", "inputHash": "64 hex"},
  "fidelity": "l0",
  "state": "completed",
  "metrics": [
    {"name": "dailyCoolingEnergy", "value": 5.482, "unit": "kWh",
     "aggregation": "representative_day", "method": "l0_steady_state", "fidelity": "l0"},
    {"name": "dailyCost", "value": null, "unit": "currency",
     "missing_reason": "缺少币种或电价；不编造费用",
     "aggregation": "representative_day", "method": "l0_steady_state", "fidelity": "l0"}
  ],
  "quality": {"state": "passed", "checks": [{"name": "energy_balance", "state": "passed", "max_residual_W": 0}]},
  "assumptions": ["…"],
  "startedAt": "…", "finishedAt": "…"
}
```

| 字段 | 约束 |
|---|---|
| identity | 与 RunInput 三元组一致；报告与对比只能引用固定 run |
| state | `completed` / `failed` / `cancelled`；失败时附 `error:{kind,message}`，事件与日志保留证据 |
| metrics[] | `value` 为 null 时必须带 `missing_reason`；null 缺失**不作为 0** 参与任何统计。数值型为有限 number，布尔型（如 capacityAdequate）为 boolean |
| quality.state | `passed` / `failed` / `notEvaluated`；checks 逐项可解释，质量失败的结果不得用于有效推荐 |
| assumptions | 每条假设的完整文字（L0 口径、等效 COP 等），随结果展示 |

指标语义由产生它的适配器文档定义；L0 指标见 `Plans/Execution/P3-orchestration-execution.md` 的「L0 物理口径」与 `Backend/src/simunow_worker/adapters/l0/steady_state.py` 的假设清单。跨口径（不同代表日/人数/时段）的结果不能直接求差值或节省百分比。

## worker 退出码

| 退出码 | 含义 |
|---|---|
| 0 | completed 或 cancelled（取消是正常终态） |
| 1 | 运行失败（invalid_snapshot / adapter_error），证据保留在 run 目录 |
| 3 | 输入无效（协议/字段/fidelity/哈希/身份不一致），不产生事件 |

CLI 参数本身非法由 argparse 报 stderr、退出 2，无 JSON 输出。
