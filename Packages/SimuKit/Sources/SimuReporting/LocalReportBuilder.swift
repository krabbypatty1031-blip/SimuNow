import Foundation
import SimuCore

public struct FixedReportEvidence: Sendable {
    public let request: LocalAnalysisRequest
    public let result: LocalAnalysisResult
    public let currentInputHash: String?
    public let suggestions: [SuggestionCard]
    public let cost: CostEvaluationRecord?
    public init(request: LocalAnalysisRequest, result: LocalAnalysisResult, currentInputHash: String?,
                suggestions: [SuggestionCard] = [], cost: CostEvaluationRecord? = nil) {
        self.request = request; self.result = result; self.currentInputHash = currentInputHash
        self.suggestions = suggestions; self.cost = cost
    }
}

public enum ReportRedactor {
    public static func publicReference(_ value: String?) -> String? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.user == nil,
              url.password == nil, url.query == nil, url.fragment == nil,
              ["https://developer.apple.com/augmented-reality/roomplan/", "https://developer.apple.com/documentation/realitykit",
               "https://energyplus.net/documentation", "https://doc.openfoam.com/", "https://www.ashrae.org/technical-resources/standards-and-guidelines"].contains(url.absoluteString) else { return nil }
        return url.absoluteString
    }
    public static func relationName(_ state: PreviewRelationState) -> String {
        switch state {
        case .intersectsAssumedPath: "与假设路径相交"
        case .occluded: "被家具遮挡，后方未模拟"
        case .outsideAssumedPath: "位于假设范围外，现实气流未知"
        case .notEvaluated: "不可评价，需检查位置及缺项"
        }
    }
    public static func methodName(_ kind: AnalysisKind) -> String {
        switch kind {
        case .airflowPreview: "气流方向规则预览"
        case .powerEstimate: "电量情景估算"
        case .steadyHeatBalance: "显热情景估算"
        }
    }
}

/// Consumes checked fixed evidence; never runs a solver or derives new metrics.
public enum LocalReportBuilder {
    public static func build(_ evidence: [FixedReportEvidence], comparison: ComparisonSnapshot? = nil,
                             createdAt: Date = Date()) throws -> LocalReportSnapshot {
        guard !evidence.isEmpty, evidence.count <= 12,
              Set(evidence.map { $0.result.identity.runID }).count == evidence.count,
              Set(evidence.map { $0.request.resolvedInput.snapshot.projectID }).count == 1 else {
            throw ProjectDataError.contract("报告需要同一项目的 1–12 份独立固定证据。")
        }
        let scenarios = Array(Set(evidence.map { $0.result.identity.scenarioID })).sorted { $0.uuidString < $1.uuidString }
        let targets = Array(Set(evidence.flatMap { item -> [UUID] in
            if case .airflowPreview(let p) = item.result.payload { return p.relations.map(\.seatID) }; return []
        })).sorted { $0.uuidString < $1.uuidString }
        var summaries: [ReportRunSummary] = []
        for item in evidence {
            try Task.checkCancellation()
            try NativeAnalysisCodec().validateRequest(item.request)
            try NativeAnalysisCodec().validateResult(item.result)
            guard item.request.identity == item.result.identity, item.request.method == item.result.method,
                  item.request.resolvedInput.adoptedAssumptions == item.result.assumptions,
                  item.result.checks.state == .passed else { throw ProjectDataError.contract("固定报告证据不完整或方法检查未通过。") }
            for card in item.suggestions {
                guard card.identity == item.result.identity, case .airflowPreview(let p) = item.result.payload,
                      card.profileID == p.profileID, card.profileVersion == p.profileVersion,
                      p.relations.contains(where: { $0.seatID == card.seatID && $0.sampleID == card.sampleID && $0.ruleID == card.ruleID && $0.state == card.relation && $0.hitEntityID == card.obstacleID }) else {
                    throw ProjectDataError.contract("建议没有对应固定运行的关注点证据。")
                }
            }
            var lines: [String] = []
            switch item.result.payload {
            case .airflowPreview(let p):
                lines.append("几何展示档案 v\(p.profileVersion)；路径衰减为无量纲 1。")
                for relation in p.relations {
                    let alias = "关注点\((targets.firstIndex(of: relation.seatID) ?? 0) + 1)"
                    let sample = relation.sampleID.map { "，采样 \($0.uuidString.prefix(8))" } ?? "，位置标记"
                    let safeRule = ["preview.pathIntersection.v1", "preview.occlusion.v1", "preview.unsupported.v1"].contains(relation.ruleID) ? relation.ruleID : "不支持的规则（仅历史）"
                    lines.append("\(alias)\(sample)：\(ReportRedactor.relationName(relation.state))。规则 \(safeRule)")
                    // Copy only built-in action text, never source names, notes or free-text reasons.
                    if let card = item.suggestions.first(where: { $0.seatID == relation.seatID && $0.sampleID == relation.sampleID }) {
                        switch card.relation {
                        case .intersectsAssumedPath: lines.append("可尝试调整风向避开该关注点，再生成候选预览比较。")
                        case .occluded: lines.append("请查看遮挡家具，并在调整后重新预览；家具后的绕流未模拟。")
                        case .outsideAssumedPath, .notEvaluated: break
                        }
                    }
                }
            case .powerEstimate(let p):
                lines.append("声明时段：" + p.requestedWindows.map { "\($0.startMinute)–\($0.endMinute) min" }.joined(separator: "、"))
                lines.append(p.totalEnergyKWh.map { "该时段电量：\($0) kWh" } ?? "电量不可完整估算；缺少覆盖时段或功率依据。")
                if let cost = item.cost {
                    guard cost.parentIdentity == item.result.identity, cost.projectID == item.request.resolvedInput.snapshot.projectID else { throw ProjectDataError.contract("费用引用了其他运行。") }
                    _ = try NativeAnalysisCodec().encodeCostEvaluation(cost)
                    let currency = cost.configuration.currency ?? "币种未知"
                    lines.append(cost.payload.totalCostDecimal.map { "声明时段费用：\($0) \(currency)" } ?? "费率、币种或覆盖时段缺失，费用不可完整估算。")
                    lines.append("费用证据：\(cost.evaluationHash)；详见原项目中的固定评价。")
                }
            case .steadyHeatBalance(let p):
                lines.append(p.coolingSensibleWatts.map { "声明工况显热制冷需求：\($0) W" } ?? "显热需求不可完整估算。")
                lines.append("不包含湿度、潜热、逐点温度或完整舒适评价。")
            }
            let assumptions = item.result.assumptions.map { assumption in
                let reference = ReportRedactor.publicReference(assumption.source.reference)
                return "假设依据：\(sourceName(assumption.source.kind))，版本 \(assumption.version)" + (reference.map { "；\($0)" } ?? "；私有备注与引用已删减")
            }
            summaries.append(.init(reference: .init(runID: item.result.identity.runID, scenarioID: item.result.identity.scenarioID,
                inputHash: item.result.identity.inputHash, method: item.result.method, evaluationHash: item.cost?.evaluationHash),
                scenarioAlias: "方案\((scenarios.firstIndex(of: item.result.identity.scenarioID) ?? 0) + 1)",
                basis: item.result.basis, checks: item.result.checks.state,
                historical: item.currentInputHash != item.result.identity.inputHash, lines: lines,
                assumptions: assumptions, missingReasons: item.result.missingReasons.map { _ in "固定运行存在缺项；详细字段与原始原因保留在本地项目。" }))
        }
        if let comparison {
            guard comparison.projectID == evidence[0].request.resolvedInput.snapshot.projectID,
                  comparison.runs.allSatisfy({ reference in summaries.contains { $0.reference == reference } }) else {
                throw ProjectDataError.contract("报告缺少固定比较所引用的证据。")
            }
        }
        // Comparison free-text may contain private source values. Keep reference/context identity;
        // export only the known numerical metric values, with generic missing/ranking labels.
        let safeComparison = comparison.map { value in
            ComparisonSnapshot(comparisonID: value.comparisonID, projectID: value.projectID, runs: value.runs,
                comparisonContextHash: value.comparisonContextHash, comparableItems: [],
                incomparableReasons: value.incomparableReasons.map { _ in .init(code: "comparison_missing", fieldPath: "", reason: "口径或输入存在缺项，详细依据保留于原项目。") },
                metrics: value.metrics?.map { metric in
                    .init(metric: ["energy", "referenceCost", "coolingSensible", "qualitativePathRelations"].contains(metric.metric) ? metric.metric : "declaredMetric",
                          unit: ["kWh", "W", "1", "CNY", "USD", "EUR"].contains(metric.unit) ? metric.unit : "declaredUnit",
                          baseline: metric.baseline, candidate: metric.candidate, absoluteDifference: metric.absoluteDifference,
                          percentDifference: nil, reasons: ["仅对应原固定比较的条件，不保证现实收益。"], ranking: "查看固定比较条件") })
        }
        return .init(createdAt: createdAt, runs: summaries, comparison: safeComparison)
    }
    private static func sourceName(_ source: ParameterSource) -> String {
        switch source { case .scan: "扫描"; case .measured: "测量"; case .manufacturer: "厂家资料"; case .user: "用户声明"; case .preset: "预设"; case .assumed: "明确假设" }
    }
}
