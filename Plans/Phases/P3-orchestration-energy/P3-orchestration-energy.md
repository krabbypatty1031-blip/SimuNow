# P3：任务编排与能耗

## 目标与前置

连接 App → worker → L1 → 结果，并建立 L2 可复用任务框架。前置 P1 初步通过与 P2 可运行模型。

## 功能、设计与技术

Mac CLI/helper adapter、JSONL 进度、独立 run 目录、输入哈希、缓存、取消、超时、L1 指标与边界转换。
Swift actor / async、Foundation Process（Mac）、Python subprocess、原子文件、EnergyPlus epJSON/IDF。CPU任务和 UI 状态隔离。

## 工作项

| ID | 工作 | 验收 |
|---|---|---|
| P3-01 | Request/Event/Result schema 与解析器 | 乱序、截断、错 run 有处理 |
| P3-02 | 本地执行器、stderr 日志、取消进程树 | 取消幂等，失败保留证据 |
| P3-03 | 时间表/天气到 L1，容量与电耗分开 | 代表日与单位有效 |
| P3-04 | L1 到送风/壁面/热源边界转换 | 送风温度依据，热源守恒 |
| P3-05 | 缓存、新鲜度、超时和恢复策略 | 旧任务不覆盖当前方案 |
| P3-06 | worker 接真实 EnergyPlus | 缺引擎不编造瓦特 |
| P3-07 | 占用时段写入 IDF 日程 | 改人数/时段进入代表日 |
| P3-08 | Workspace 提交 L1 | 未配置不可点；任务页有进度 |
| P3-09 | 沙盒下选择引擎与工作副本 | 不关 sandbox；路径不进 project.json |
| P3-10 | 电耗/边界展示与失败安全 | 旧结果 stale；取消不坏项目 |

## 关键实现

测试 request 的 input hash 与实际快照一致。日志不含个人房间标签；资源限制按 P1 实测制定。
选等效电耗时显示方法/有效COP/辅机范围；采用真实设备对象则从对应输出取电耗，不重复除 COP。
App sandbox 下进程、路径、容器桥接需要打包验证；架构支持受控 helper 或独立 companion，不能假定 Process 自动取得权限。
iOS 只消费接口/文件结果；远程 adapter 后续接入且不默认上传。

## 子任务索引

可验收拆分（writing-plans + inline 执行）。状态只在本目录勾选，事实结论仍只写 `Plans/Delivery/status.md`。

| 父项 | 子任务文件 | 证明什么 |
|---|---|---|
| P3-01 | [P3-01-task-protocol.md](P3-01-task-protocol.md) | request/event/result 可解析；乱序/截断/错 run 被拒绝 |
| P3-02 | [P3-02-local-executor.md](P3-02-local-executor.md) | Mac 本地 worker、JSONL、取消幂等、失败留证 |
| P3-03 | [P3-03-l1-representative-day.md](P3-03-l1-representative-day.md) | 代表日 L1；冷量与电耗分开 |
| P3-04 | [P3-04-boundary-map.md](P3-04-boundary-map.md) | L1→边界；送风 T 不是设定 T |
| P3-05 | [P3-05-cache-freshness.md](P3-05-cache-freshness.md) | 缓存与超时不覆盖当前方案 |
| P3-06 | [P3-06-real-l1.md](P3-06-real-l1.md) | worker 跑 EnergyPlus 代表日 |
| P3-07 | [P3-07-occupied-schedule.md](P3-07-occupied-schedule.md) | 占用时段进入 IDF，不是 AlwaysOn |
| P3-08 | [P3-08-workspace-submit.md](P3-08-workspace-submit.md) | Mac 工作区提交不可变 L1 |
| P3-09 | [P3-09-sandbox-engines.md](P3-09-sandbox-engines.md) | 用户选择引擎；sandbox 保持 |
| P3-10 | [P3-10-result-safety.md](P3-10-result-safety.md) | 进度/电耗/边界；失败不坏项目 |
| P3-11 | [P3-11-sandbox-app-l1.md](P3-11-sandbox-app-l1.md) | 沙盒 App 用包内 worker + 用户引擎跑 L1 |

总清单：[P3-checklist.md](P3-checklist.md)。未勾选不得把 P3 标为完成。三维场、舒适推荐、全年节能属于 P4/P5。未配置引擎时不得出现空的「开始计算」；真实提交按钮文案为「提交代表日 L1」。

## 验收与降级

Mac 更改代表日或人数，提交任务，看到进度、电耗与边界；退出与失败不损坏项目。
没有真实曲线时使用有来源的等效性能并做范围分析；不以额定制冷功率充当耗电。
