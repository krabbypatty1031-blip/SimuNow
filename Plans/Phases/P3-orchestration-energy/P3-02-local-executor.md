# P3-02 本地执行器、日志、取消

**Files:**

- Create: `Packages/SimuKit/Sources/SimuSimulation/LocalProcessClient.swift`（`#if os(macOS)`）
- Create: `Backend/src/simunow_worker/task_runner.py`（读 request，写 JSONL，不在本步接 EnergyPlus）
- Test: 进程夹具 / Swift 取消测试
- 依赖：P3-01

**Interfaces:**

- Consumes: `SimulationRequest`、`TaskEventStream`
- Produces: 独立 `runs/<run-id>/`（events.jsonl、stderr.log）；`cancel` 幂等
- 不产生：App「开始计算」按钮（要等 P3-03 真 L1 通了再开）；iOS Process

**约束：**

- stdout 只允许 JSONL 事件
- stderr 进日志；剥离用户家目录
- 取消已结束的 run 仍成功（幂等）
- 失败必须留下 request 快照与日志
- sandbox 失败要记证据，不得关沙盒

---

### P3-02a 启动与 JSONL

- [x] 假 worker 只打印 accepted/progress/completed
- [x] 客户端按 P3-01 解析

### P3-02b 日志

- [x] stderr 写入 `runs/<id>/logs/stderr.log`
- [x] 不含 `/Users/<name>/`

### P3-02c 取消

- [x] 取消执行中进程树
- [x] 再 cancel 一次不抛

### P3-02d 失败证据

- [x] worker 非 0 退出 → failed 事件 + 目录仍在

### P3-02e 未配置

- [x] 引擎探测失败仍是 `engineNotConfigured`，不得 `succeeded`
