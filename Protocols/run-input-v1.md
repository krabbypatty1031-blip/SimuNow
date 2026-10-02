# RunInput v1：一次运行的不可变输入

P3 新增。RunInput 是 App 提交给 worker 的唯一运行请求，把一个 `ScenarioInputSnapshot` 提升为可执行、可核对、可缓存的运行身份。本协议只描述输入文件；事件流与结果见 [run-events-v1.md](run-events-v1.md)。

- 协议标识：`run-input/1`；camelCase；UTF-8 JSON。
- 实现：Swift `SimuSimulation/RunProtocols.swift`（写入），Python `simunow_worker/jobs/runner.py`（读取）。
- Schema：[Schemas/run-input.schema.json](Schemas/run-input.schema.json)。快照部分的完整约束由 [project-model-v2.md](project-model-v2.md) 与 scenario-input-snapshot schema 定义，本文件不重复。

## 结构

```json
{
  "protocol": "run-input/1",
  "runID": "3392F7E1-…",
  "scenarioID": "…",
  "inputHash": "64 hex",
  "fidelity": "l0",
  "snapshot": { "schemaVersion": 2, "…": "ScenarioInputSnapshot" },
  "settings": { }
}
```

| 字段 | 必需 | 约束 |
|---|---|---|
| protocol | 是 | 常量 `run-input/1` |
| runID | 是 | 规范 UUID；一次运行全局唯一，worker 只写 `runs/<runID>/` 自己的目录 |
| scenarioID | 是 | 必须与 `snapshot.scenarioID` 一致，否则输入无效 |
| inputHash | 是 | 64 位小写/大写 hex；必须等于对 `snapshot` 的规范文本 SHA-256（见下节） |
| fidelity | 是 | 当前仅 `l0`；请求未配置的保真度被拒绝（退出 3），不产生部分结果 |
| snapshot | 是 | 完整 ScenarioInputSnapshot v2 wire 结构；evaluation 参与哈希但只用于费用估算 |
| settings | 否 | 求解设置占位；L0 为确定性计算，当前无已定义键。未知可选字段保留兼容 |

## 输入哈希

哈希是对 `snapshot` 字段（不含信封）的规范文本做 SHA-256：

1. 对象键按 UTF-8 字节序排序，无空白；数组保持顺序。
2. 字符串只转义 `"`、`\` 与控制字符（短转义优先，其余 `\u00xx` 小写）；非 ASCII 按 UTF-8 原样通过。
3. 数字保留 wire 上的原始 token（`1.50`、`1e2`、`-0` 不规范化）。

Swift `InputHash` 与 Python `models/hashing.py` 双实现；契约交换对同一快照比较两端哈希，见 `Backend/tests/contract_exchange.py` 与 `Packages/SimuKit/Tests`。修改快照内任何参与物理或费用评价的字段都会改变哈希；显示状态本就不在快照内。

## worker 侧校验顺序

worker 在发出任何事件之前先解析信封：协议错误、缺字段、fidelity 未配置 → stderr 诊断，退出 3，**不产生事件**（事件不能挂在不可信的 runID 上）。进入运行后：快照结构非法 → failed 事件 + 退出 1；`inputHash` 与实算不符 → failed（`input_hash_mismatch`）+ 退出 3；信封 `scenarioID` 与快照不一致 → 同样视为无效输入。哈希通过才执行适配器，保证「请求身份 = 实际输入」。

## 取消与目录

客户端写 `<runDir>/cancel-requested` 标记文件请求取消；worker 在计算步之间轮询，开始前已存在标记也产生 cancelled 结果而非崩溃；重复取消无害。取消与拒绝新任务是不同操作；worker 不吞异常。

run 目录内容：`input.json`（客户端写入的本协议文件）、`events.jsonl`、`result.json`、失败时的 `stderr.log`。目录位置当前由客户端决定（见 decisions.md ADR-014）；目标布局（项目包内 `runs/<run-id>/`）见 `Plans/References/04-data-contracts.md`，迁移时记录。
