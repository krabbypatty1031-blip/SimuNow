import Foundation
import SimuCore
import SimuReporting
import SimuSimulation

/// Builds the fixed report snapshot from completed, quality-passed, current runs only.
/// Formatting only — no metric is recomputed here (P5 evidence rule).
public enum ReportBuilder {

    public static let scopeStatements: [String] = [
        "本报告数值来自 L0 集总平均估算（l0_steady_state）：总量与平均值，不是逐点 CFD 结果。",
        "代表日结果不能外推全年；本报告不提供年度费用与回收期。",
        "缺失值显示为缺失，不以 0 计入任何统计。",
        "位置级舒适（PMV/吹风/温差）需 L2 CFD，本报告未评价。",
        "每组数值可追溯到固定 run ID 与输入哈希；修改输入后旧结果标记「待重算」且不再收录。",
    ]

    public static let limitations: [String] = [
        "L1 EnergyPlus 与 L2 OpenFOAM 未配置（可用 doctor 诊断环境）；本报告不含其输出。",
        "未做现场实测校准（P6）；模型误差范围未知。",
        "天气为显式假设或引用文件，未与气象站核验。",
        "容量充足性为 L0 代表日口径，不构成设备选型检定。",
    ]

    /// Entries: eligible rows only. Returns nil when nothing honest can be reported.
    public static func content(project: ProjectDocument, rows: [ComparisonModel.Row],
                               cards: [ComparisonModel.Card], generatedAt: Date = Date()) -> ReportContent? {
        let (_, members, excluded) = ComparisonModel.mainBasisGroup(rows: rows)
        let reportable = members.filter { $0.eligibility == .eligible }
        guard !reportable.isEmpty else { return nil }

        let entries = reportable.map { entry(for: $0, project: project) }
        var cardLines = cards.map { ReportContent.CardLine(title: $0.title, body: $0.body) }
        if !excluded.isEmpty {
            cardLines.append(ReportContent.CardLine(
                title: "口径说明",
                body: "\(excluded.count) 个有效方案因天气/人数/时段口径不同未参与对比排序：\(excluded.map(\.scenarioName).joined(separator: "、"))。"))
        }
        return ReportContent(projectName: project.name, generatedAt: generatedAt,
                             scopeStatements: scopeStatements, entries: entries,
                             cards: cardLines,
                             unknownsAndAssumptions: AssumptionCollector.items(in: project),
                             limitations: limitations)
    }

    private static func entry(for row: ComparisonModel.Row, project: ProjectDocument) -> ReportContent.Entry {
        let result = row.record?.result
        let metrics = (result?.metrics ?? []).map { metric in
            ReportContent.MetricLine(
                title: RunsMetricTitles.title(for: metric.name),
                value: metric.isMissing
                    ? "缺失：\(metric.missingReason ?? "未知原因")"
                    : metric.boolValue.map { $0 ? "是" : "否" }
                        ?? "\(metric.doubleValue.map(ComparisonModel.format) ?? "?") \(metric.unit)")
        }
        return ReportContent.Entry(
            scenarioName: row.scenarioName,
            runID: row.record?.identity.runID.uuidString ?? "?",
            inputHash: row.record?.identity.inputHash ?? "?",
            fidelity: "L0 平均估算",
            quality: result?.quality.state == .passed ? "通过" : "未通过",
            representativeDate: row.representativeDate,
            metrics: metrics,
            assumptions: result?.assumptions ?? [],
            costLines: costLines(for: row, project: project))
    }

    /// Cost layering: quotes are one-off amounts with currency; missing stays 待报价, never zero.
    private static func costLines(for row: ComparisonModel.Row, project: ProjectDocument) -> [String] {
        guard let scenario = project.scenarios.first(where: { $0.id == row.scenarioID }) else { return [] }
        let cost = scenario.evaluation.cost
        var lines: [String] = []
        if let currency = cost.currency { lines.append("币种：\(currency)") }
        if cost.tariffs.isEmpty && cost.quotes.isEmpty {
            lines.append("费用：待报价/待电价（不以 0 计）")
        }
        for tariff in cost.tariffs {
            let rate = tariff.rate.value.map { ComparisonModel.format($0) } ?? "未知"
            lines.append("电价时段 \(tariff.startMinute)–\(tariff.endMinute) min：\(rate) \(cost.currency ?? "币种未填")/kWh")
        }
        for quote in cost.quotes {
            if let amount = quote.amount.value {
                lines.append("一次性报价：\(ComparisonModel.format(amount)) \(cost.currency ?? "币种未填")")
            } else {
                lines.append("一次性报价：待报价")
            }
        }
        return lines
    }
}

/// Shared display titles for known L0 metric names.
public enum RunsMetricTitles {
    public static func title(for name: String) -> String {
        [
            "averageRoomTemperature": "平均室温",
            "coolingLoadPeak": "峰值冷负荷",
            "dailyCoolingEnergy": "日冷量（热）",
            "estimatedElectricEnergy": "估算电耗（等效 COP）",
            "capacityAdequate": "容量是否充足",
            "dailyCost": "日费用",
        ][name] ?? name
    }
}
