# P5 执行计划：方案对比、建议卡与基础报告（2026-10-03，development 分支）

展开 `Plans/Phases/P5-decision-and-report.md` 中不依赖外部引擎的部分。本机无 EnergyPlus/OpenFOAM（L1/L2 not_configured），因此**全部对比与建议只基于 L0 平均估算**：L0 只对容量、总量能耗与费用口径做筛选（硬约束 5；`Plans/References/05-computation-and-decision.md`「先 L0/L1 筛选容量、能耗、预算」）。位置级舒适属于 L2，一律显示「未评价」，不伪造。

## 范围与不做的事

| 做 | 不做（及原因） |
|---|---|
| 基准/候选方案的 L0 结果对比表（同口径校验） | 风向/角度类候选（L0 不含气流方向，硬约束 5） |
| 设定温度候选生成（±1 °C，L0 对设定敏感） | Pareto/NSGA-II（P7；先可解释三方案表） |
| 三类建议卡（运行调整/容量配置/舒适改善） | 舒适定量结论（需 L2）；年度费用与回收期（硬约束 9） |
| 基础 PDF 报告（文本型，含 run 身份与假设） | 图表排版复杂版；从 View 重算指标（报告只读固定 run 结果） |
| 失败/缺失/过期结果的诚实呈现 | 「达标座位比例」等位置级指标（无 L2） |

## 数据与规则

- 参与对比的 run 必须同时满足：`state=completed`、`quality.state=passed`、新鲜度 current（inputHash 等于当前方案快照哈希）。stale 结果显示「待重算」且不参与对比；质量失败禁止推荐（硬约束 7）。
- 同口径判定：方案间比较要求「比较基准」一致——`inputs.environment`（代表日/时区/天气引用/温湿度）与 `inputs.usage`（座位/人员/设备热源）的规范序列化逐字相等；不同则标记「口径不同」，不同组之间不排序（05 节「跨口径结果不能直接求节省百分比」）。
- 候选生成：仅改动 `Control.setpoint`（±1 °C，复制方案 + 新 scenarioID，实体 ID 保留）；设定未知时不生成。生成动作写入假设可见的说明。
- 建议卡规则（每条附 runID 短码、method、代表日与假设数）：
  1. 运行调整：同口径且容量充足的方案中，估算电耗最低者（费用数据齐全时同时列出日费用）。并列或不足两个方案时说明。
  2. 容量配置：任一方案 `capacityAdequate=false` → 指出峰值负荷（W）与「代表日容量不足」，建议核实设备容量；不编造具体机型报价。
  3. 舒适改善：固定说明位置级舒适需 L2 CFD，当前不可评价；这是状态而非建议结论。
  - 无可行方案（无有效 run 或全部容量不足）→ 明确解释，不强行推荐（P5-02 降级）。
- 费用分层：`dailyCost` 来自电价时段（L0 已算）；`quotes` 按币种列出为一次性费用；缺失显示「待报价」，不以 0 计；不出现年度外推与回收期。

## 模块与文件

| 文件 | 责任 |
|---|---|
| `SimuWorkspace/Comparison/ComparisonModel.swift` | 纯逻辑：有效 run 筛选、同口径分组、对比行、建议卡生成、候选生成；可单测 |
| `SimuWorkspace/Comparison/ComparisonView.swift` | 方案对比页（表格 + 建议卡 + 生成候选 + 费用分层） |
| `SimuReporting/ReportContent.swift` | 报告内容快照（只读数据，不含计算） |
| `SimuReporting/BasicReportExporter.swift` | CoreGraphics/CoreText 文本型 PDF（A4、分页）；双平台 |
| `SimuWorkspace/Reporting/ReportView.swift` | 报告页：预览摘要 + 导出（Mac 保存面板 / iOS 分享） |

PDF 决策：CoreGraphics PDF context + CTFramesetter 文本排版（系统字体含中文 fallback，文本可选中）。备选 ImageRenderer 位图化（文本不可选）与三方库（引入依赖）均不取。记录为 ADR。

## 报告内容顺序

标题/项目/生成时间 → 范围声明（L0 平均估算非 CFD；代表日不推全年；缺失不填 0；未做现场实测）→ 方案对比表（方案、run 短码、哈希短码、质量、新鲜度、代表日、关键指标含单位、费用/待报价）→ 建议卡（含依据 run 与方法）→ 假设与未知清单 → 限制与待补测（L1/L2 未配置、舒适未评价、年度费用不提供）。

## 测试与验收

- 单测（SimuCoreTests）：有效 run 筛选（stale/failed/notEvaluated 排除）、同口径分组、候选生成身份规则、建议卡选择与诚实文案（含 runID、无位置级数值）、报告内容构建、PDF 导出产生有效 PDF（%PDF 头、分页、非空）、无有效 run 时导出被阻止并解释。
- 集成：FakeRunClient 三方案 → 对比 → 卡片 → 导出 PDF 全链路非 UI 测试。
- 验收命令：`Scripts/check.sh all`；App 内演示路径（模板 → 补全未知 → 跑三方案 → 对比 → 导出 PDF）需用户本机手动执行并记录。
