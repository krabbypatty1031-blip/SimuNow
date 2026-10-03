# P3 可验收清单

> 给执行者：按 `P3-01` → `P3-05` 顺序。勾选后把命令与证据写入 `Plans/Delivery/status.md`。

**Goal:** Mac 能提交不可变 L1 任务、看到 JSONL 进度，并得到带单位的电耗与边界；取消/失败不损坏项目。本阶段不把 L1 平均包装成逐点 CFD。未配置时按钮不可点；配置后文案为「提交代表日 L1」，不是空的「开始计算」。

**已有、不得再当 P3 完成证据：** P1 CLI 已跑通 EnergyPlus / OpenFOAM；P2 房间编辑与模板；`UnconfiguredSimulationClient` 抛错。

**锁定（P3 全程沿用）：**

- 任务 JSON 与现有 request/receipt 一样用 camelCase，CodingKeys 显式写出
- `inputHash` 必须对得上快照字节；旧 run 不得覆盖当前方案
- 设定温度 ≠ 送风温度；制冷量 ≠ 电功率
- 循环回风 ≠ 室外新风
- 进度不是残差百分比；未知指标用 omitted / null，不填 0
- 日志不含个人房间标签与绝对家目录
- iOS 不接 Process；Mac sandbox 不以关闭沙盒为修复
- 没有真实执行前，工作区不出现可点的计算按钮

## P3-01 任务协议

- [x] P3-01a request 带相对快照路径与哈希，且与快照一致
- [x] P3-01b JSONL 事件可解析；乱序 sequence 拒绝
- [x] P3-01c 截断行不静默当成完整事件
- [x] P3-01d 错 runID 的事件不进入当前流
- [x] P3-01e result 有单位指标；缺失不是 0
- [x] P3-01f Swift / Python / schema / fixture 同步

## P3-02 本地执行器

- [x] P3-02a Mac adapter 启 worker，stdout 只收 JSONL
- [x] P3-02b stderr 进 run 日志，不含家目录路径
- [x] P3-02c 取消幂等，能杀进程树
- [x] P3-02d 失败保留 run 目录证据
- [x] P3-02e 未配置引擎仍不可产生 succeeded

## P3-03 L1 代表日

- [x] P3-03a 时间表/天气进入 L1，文件带哈希
- [x] P3-03b 制冷量与电功率分字段
- [x] P3-03c 代表日单位与方法写进 result

## P3-04 边界转换

- [x] P3-04a L1 → 送风/壁面/热源边界
- [x] P3-04b 送风温度有依据，不是设定温度
- [x] P3-04c 热源守恒，不重复计入

## P3-05 缓存与恢复

- [x] P3-05a 相同 inputHash 可复用，freshness 独立
- [x] P3-05b 超时与恢复不覆盖当前方案
- [x] P3-05c 旧任务只进入所属 run

## P3-06 真实 L1

- [x] P3-06a 草稿映射到 L1 房间，不伪造 UA
- [x] P3-06b 缺引擎 failed，不编造瓦特
- [x] P3-06c 有 EnergyPlus 时写出冷量与电耗

## P3-07 占用时段

- [x] P3-07a office 日程进入 L1 房间
- [x] P3-07b IDF Compact，无日程才 AlwaysOn
- [x] P3-07c 人数进入 People，不是座位数

## P3-08 Workspace 提交

- [x] P3-08a 人数与占用时段可写
- [x] P3-08b 未配置不可提交；配置后有 receipt/事件
- [x] P3-08c 无「开始计算」字符串

## P3-09 沙盒引擎

- [x] P3-09a 工作副本 + EnergyPlus 才配置
- [x] P3-09b sandbox 保持；书签不进 project.json
- [x] P3-09c 有引擎时可从 L1 客户端跑通

## P3-10 结果与安全

- [x] P3-10a 电耗/边界展示，年电量未知
- [x] P3-10b 改输入后 stale
- [x] P3-10c 取消/失败不改当前草稿

## P3-11 沙盒 App L1

- [x] P3-11a 系统 Python 3.9 可启动 worker
- [x] P3-11b worker 打进 App 并 stage 到容器
- [x] P3-11c 只需选择引擎目录；sandbox 保持
