# P3-05 缓存、新鲜度、超时和恢复

**Files:**

- 执行器旁路：相同 `inputHash` 复用 run 目录
- `RunIdentity.freshness` 已有；接到提交路径
- 依赖：P3-02；L1 指标依赖 P3-03

**Interfaces:**

- Consumes: request + 当前方案 inputHash
- Produces: 命中缓存的 receipt/result；超时 failed；恢复不改 project.json
- 不产生：覆盖当前编辑、删除失败 run

**约束：**

- 旧任务只进入其 run 目录
- 编辑房间后旧 result 标 stale
- 超时与取消一样保留证据

---

### P3-05a 缓存

- [x] 相同哈希不新开求解；返回原 runID

### P3-05b 超时

- [x] 超时 → failed + 日志；project 仍是用户当前稿

### P3-05c 恢复

- [x] 崩溃后再打开包，未完成 run 不自动改当前方案
