# P1-05 粗/中网格与性能

**Files:**

- Create: `test/p1/mesh_study.py`
- Evidence: `test/outputs/p1_mesh/perf_table.json` 与一行人读结论 `perf_table.md`
- 依赖：P1-03h 房间脚本可调网格密度

P1 原文只要粗/中两套。**三网格系统检查与现场验证不在本任务**（写进 P1-05e，避免做完两套就宣称网格无关）。

---

### P1-05a 粗网格

- [x] 在 `room_p1.json` 上降低 `blockMesh` 单元数（例如每向约一半，具体数写入报告）
- [x] 记录：wall-clock s、峰值 RSS MB、`checkMesh`、质量误差、能量误差、是否 `quality.pass`
- [x] 座位样本保存为 `samples_coarse.json`

通过：有真实本机数字。失败：抄 P0 Python 的 1.06s 当 OpenFOAM 耗时。

### P1-05b 中网格

- [x] 与粗网格同一输入哈希（仅网格参数不同，**网格密度必须进入 input_hash**）
- [x] 同样指标写入 `samples_medium.json`

通过：两套 `input_hash` 不同（因网格字段）。失败：改了网格却宣称同一哈希。

### P1-05c 指标对比

- [x] 对每个座位：ΔT、Δ|U|
- [x] `|U|` 低于 0.05 m/s 时以绝对误差为主，不报上千百分数
- [x] 不因粗网格座位排序变化就宣称「方案推荐稳定」（P1 无推荐）

通过：表中每个座位两列都有数或 `missing`。失败：用显示降采样网格代替求解网格统计。

### P1-05d 可行规模

`perf_table.md` 必须有且仅有一段结论，模板：

```text
本机 arm64 + OpenFOAM 2512 容器：粗网格 Xs / Y MB，中网格 Xs / Y MB。
比赛默认采用 <coarse|medium>，因为 <质量通过且时间可接受的理由>。
未做第三套网格，不能声称网格无关。
```

通过：数字与 JSON 一致。失败：空话「性能良好」无秒数。

### P1-05e 明确裁剪

- [x] 清单里写：第三套网格、现场热电偶、PMV、App 切片渲染 = 后续阶段
- [x] 不得把 P1-05 标成「验证完成、可用于定量推荐」

通过：本条存在且 status 不把 P1 写成产品验证。失败：用两套网格差给置信度百分比。
