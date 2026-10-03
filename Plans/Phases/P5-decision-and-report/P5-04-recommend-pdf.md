# P5-04 三类建议、DeepSeek 对比说明

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/ReportEvidence.swift`
- Create: `Packages/SimuKit/Sources/SimuCore/Recommendation.swift`
- Create: `Packages/SimuKit/Sources/SimuReporting/EvidencePDFAssembler.swift`（macOS Core Graphics / Core Text）
- Create: `Packages/SimuKit/Sources/SimuReporting/ReportNarrator.swift`
- Create: `Packages/SimuKit/Sources/SimuReporting/DeepSeekReportClient.swift`（DeepSeek 官方 `POST /chat/completions`）
- Create: `Packages/SimuKit/Sources/SimuReporting/ReportWriterSkill.swift`（DeepSeek 系统提示词）
- Create: `.cursor/skills/llm-report/SKILL.md`
- Create: `Backend/src/simunow_worker/models/recommend.py`
- Create: `Protocols/Schemas/report-evidence.schema.json`
- Modify: `Packages/SimuKit/Sources/SimuReporting/ReportContract.swift`
- Modify: `WorkspaceView` 报告页：建议卡 + 导出 PDF
- Test: `RecommendationTests`、`ReportEvidenceTests`、`NarratorGuardTests`

**Interfaces:**

- Consumes: 已 pin 且 quality 可用的 `CandidateRun`、P5-02 可行性、P5-03 费用、ADR-015、ADR-019
- Produces: `ReportEvidence`；`RecommendationCard`（三类）；`GeneratedReport`；PDF 文件
- 不产生：模型重算的瓦数/比例/费用；合规证书；全局最优；无密钥时的替身 PDF

**建议三类（代码分类，模型只写 prose）：**

| kind | 何时出现 | 必须引用 |
|---|---|---|
| `operation` | 同口径下设定/风量/占用可调，且有 L1 电费差或明确「无电费差」 | L1 run ID |
| `comfort` | 同口径几何变化（如送风高度）改变座位温或达标比例 | L2 run ID、质量 passed |
| `retrofit` | 需要改设备/安装；无报价则结论为待报价，不写回收期 | 假设列表 |

规则：先约束/容量，再舒适，再费用。无可行 L2 → 出解释卡，不出假推荐。多目标并排，不合成单一分数。

**PDF 两层：**

1. **证据层（必须）**：表内数字 = `ReportEvidence` 字段。含 run ID、inputHash、quality、座位带、达标比例、代表日 kWh/HKD、舒适假设、电价 reference。
2. **说明层（DeepSeek，ADR-019 / ADR-020）**：`ReportGenerator.generate(evidence)` → 标题、总述、四节（EnergyPlus、OpenFOAM、方案对比、建议）。官方 `POST https://api.deepseek.com/chat/completions`。密钥 `DEEPSEEK_API_KEY` 或 `SIMUNOW_REPORT_API_KEY` 或钥匙串。无密钥不能导出。提示词见 `ReportWriterSkill`。

叙述守卫：从 prose 抽出的数字必须是证据包数值集合的子集（允许 run ID 短前缀、两位小数展示值、单位换算后的已列值）。否则该段丢弃并注明未采用。无密钥 / 网络失败 → 不写 PDF。

---

### P5-04a 结构化建议

- [x] 两个同口径 L2 候选：送风高度不同 → 至少一张 `comfort` 卡，引用两个 L2 run ID
- [x] 无质量通过场 → 只有不可行解释，没有「推荐方案 A」
- [x] 改造卡在无报价时写待报价，字段 `payback` 不存在或 omitted

通过：卡上能点回 run。失败：无 run ID 的定性推荐。

### P5-04b 证据包与 PDF

- [x] `ReportEvidence` Codable 与 schema 一致；数字来自候选，不来自 View
- [x] 无密钥时不写替身 PDF；按钮不可点
- [x] 有生成结果时 `EvidencePDFAssembler` 写出模型正文与本地附录
- [x] 改当前草稿后，已生成报告仍引用原 run ID（冻结）

通过：PDF 打开可见 run ID、EnergyPlus/OpenFOAM 与全年电费。失败：PDF 数字与证据包不一致。

### P5-04c 叙述器守卫

- [x] 未设置 API 键 → `generate` 返回 nil，不写 PDF
- [x] 测试夹具：模型散文写入「节电 37%」而证据无此数 → 该段拒绝
- [x] 密钥不出现在 PDF、日志、project.json

通过：假数字进不了报告。失败：把模型输出原样印进 PDF。
