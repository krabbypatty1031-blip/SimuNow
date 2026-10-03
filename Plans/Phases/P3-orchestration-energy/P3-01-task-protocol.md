# P3-01 Request / Event / Result 协议与解析器

**Files:**

- Modify: `Packages/SimuKit/Sources/SimuSimulation/SimulationClient.swift`（request 增加快照路径/哈希）
- Create: `Packages/SimuKit/Sources/SimuCore/TaskProtocol.swift`
- Create: `Packages/SimuKit/Tests/SimuCoreTests/TaskProtocolTests.swift`
- Create: `Protocols/Schemas/simulation-event.schema.json`
- Create: `Protocols/Schemas/simulation-result.schema.json`
- Modify: `Protocols/Schemas/simulation-request.schema.json`
- Modify: `Protocols/README.md`
- Create: `Backend/src/simunow_worker/models/task.py`
- Create: `Backend/tests/test_task_protocol.py`
- Create: `Fixtures/task/request-l1.json`、`Fixtures/task/events-ok.jsonl`、`Fixtures/task/result-l1.json`
- Modify: `Plans/Delivery/status.md`（有测试证据后再写）

**Interfaces:**

- Consumes: 现有 `RunIdentity` / `SimulationRequest` / `RunReceipt` / `RunState`
- Produces: `SimulationEvent`、`TaskEventStream`、`SimulationResult`、`ResultMetric`；request 增加 `schemaVersion` `snapshotPath` `snapshotHash`
- 不产生：Process 执行、App 计算按钮、EnergyPlus 运行、场文件

**约束：**

- 线格式 camelCase；CodingKeys 显式
- `snapshotPath` 相对项目包，拒绝 `/Users/`、`/Downloads/`、`..`
- `identity.inputHash` 必须等于快照字节的 SHA-256 hex
- sequence 严格递增；错 run / 截断行 / 乱序都是结构化错误
- 进度 `payload.fraction` 不是残差；缺失指标 `value=null` 且 `omitted=true`，不写 0
- `UnconfiguredSimulationClient` 仍抛错

---

### P3-01a request 与快照哈希

- [x] 测试：快照 JSON 的 SHA-256 与 `inputHash`/`snapshotHash` 一致才 `validate`
- [x] 绝对路径或 `..` 被拒绝
- [x] 改一个字节后哈希失败

通过：同一夹具 Swift 与 Python 都接受。失败：只比字符串不比文件哈希。

### P3-01b 乱序事件

- [x] 测试：sequence 0,2 后出现 1 → `staleSequence`，已接收事件不变
- [x] 正常 0,1,2 进入流

通过：乱序不重排、不覆盖。失败：按 timestamp 偷偷排序。

### P3-01c 截断行

- [x] 测试：半行 JSON 留在缓冲；补上换行后才成为事件
- [x] 流结束仍有半行 → `truncatedLine`

通过：半行不解码成功。失败：吞掉半行。

### P3-01d 错 run

- [x] 测试：`runID` 与流期望不符 → `wrongRun`，不 append

通过：当前流事件数不变。失败：混进别的任务。

### P3-01e result 缺失不是 0

- [x] 测试：`p_elec_w` 可有值；`annual_kwh` omitted/null 不得变成 0
- [x] `state=succeeded` 仍要求 `quality` 独立字段

通过：解码后 omitted 指标 `value == nil`。失败：缺省 0。

### P3-01f 契约同步

- [x] schema / Swift / Python / fixture 同一套键
- [x] 无计算按钮新增

通过：`Scripts/check.sh test` 与 `python3 -m unittest Backend.tests.test_task_protocol`。失败：只改一端。
