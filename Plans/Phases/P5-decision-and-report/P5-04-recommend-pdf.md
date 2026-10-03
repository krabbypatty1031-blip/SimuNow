# P5-04 三类建议、证据 PDF、可选叙述器

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/ReportEvidence.swift`
- Create: `Packages/SimuKit/Sources/SimuCore/Recommendation.swift`
- Create: `Packages/SimuKit/Sources/SimuReporting/EvidencePDFAssembler.swift`（macOS PDFKit）
- Create: `Packages/SimuKit/Sources/SimuReporting/ReportNarrator.swift`
- Create: `Packages/SimuKit/Sources/SimuReporting/OpenAICompatibleNarrator.swift`
- Create: `Backend/src/simunow_worker/models/recommend.py`
- Create: `Protocols/Schemas/report-evidence.schema.json`
- Modify: `Packages/SimuKit/Sources/SimuReporting/ReportContract.swift`
- Modify: `WorkspaceView` 报告页：建议卡 + 导出 PDF
- Test: `RecommendationTests`、`ReportEvidenceTests`、`NarratorGuardTests`

**Interfaces:**

- Consumes: 已 pin 且 quality 可用的 `CandidateRun`、P5-02 可行性、P5-03 费用、ADR-015
- Produces: `ReportEvidence`；`RecommendationCard`（三类）；PDF 文件；可选 `ReportNarration`
- 不产生：模型重算的瓦数/比例/费用；合规证书；全局最优

**建议三类（代码分类，模型只写 prose）：**

| kind | 何时出现 | 必须引用 |
|---|---|---|
| `operation` | 同口径下设定/风量/占用可调，且有 L1 电费差或明确「无电费差」 | L1 run ID |
| `comfort` | 同口径几何变化（如送风高度）改变座位温或达标比例 | L2 run ID、质量 passed |
| `retrofit` | 需要改设备/安装；无报价则结论为待报价，不写回收期 | 假设列表 |

规则：先约束/容量，再舒适，再费用。无可行 L2 → 出解释卡，不出假推荐。多目标并排，不合成单一分数。

**PDF 两层：**

1. **证据层（必须）**：表内数字 = `ReportEvidence` 字段。含 run ID、inputHash、quality、座位带、达标比例、代表日 kWh/HKD、舒适假设、电价 reference。
2. **叙述层（可选）**：`ReportNarrator.narrate(evidence)` → 标题与各卡段落。OpenAI 兼容 `chat/completions`。密钥 `SIMUNOW_REPORT_API_KEY` 或钥匙串。

叙述守卫：从 prose 抽出的数字必须是证据包数值集合的子集（允许 run ID 短前缀、单位换算后的已列值）。否则该段丢弃并注明未采用。无密钥 / 网络失败 → 仍导出证据 PDF。

---

### P5-04a 结构化建议

- [ ] 两个同口径 L2 候选：送风高度不同 → 至少一张 `comfort` 卡，引用两个 L2 run ID
- [ ] 无质量通过场 → 只有不可行解释，没有「推荐方案 A」
- [ ] 改造卡在无报价时写待报价，字段 `payback` 不存在或 omitted

通过：卡上能点回 run。失败：无 run ID 的定性推荐。

### P5-04b 证据包与 PDF

- [ ] `ReportEvidence` Codable 与 schema 一致；数字来自候选，不来自 View
- [ ] 无叙述器时 `EvidencePDFAssembler` 写出含表格与假设的 PDF
- [ ] 改当前草稿后，已生成报告仍引用原 run ID（冻结）

通过：PDF 打开可见 run ID 与「演示假设，非真实电价」。失败：PDF 数字与证据包不一致。

### P5-04c 叙述器守卫

- [ ] 未设置 API 键 → `narrate` 返回 nil，PDF 仍成功
- [ ] 测试夹具：模型散文写入「节电 37%」而证据无此数 → 该段拒绝
- [ ] 密钥不出现在 PDF、日志、project.json

通过：假数字进不了报告。失败：把模型输出原样印进 PDF。
