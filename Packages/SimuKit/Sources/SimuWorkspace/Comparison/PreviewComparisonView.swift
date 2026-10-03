import SimuCore
import SimuSimulation
import SwiftUI

public struct PreviewComparisonRow: Equatable, Sendable, Identifiable {
    public let scenarioID: UUID
    public let name: String
    public let result: LocalAnalysisResult?
    public let reason: String?
    public var id: UUID { scenarioID }
}
public enum PreviewComparisonBuilder {
    public static func rows(
        project: ProjectDocument, configuration: AnalysisConfigurationStore?, results: [LocalAnalysisResult],
        registry: ModelRegistry = .builtIn, additionalIssues: [ValidationIssue] = []
    ) -> [PreviewComparisonRow] {
        var profile: AirflowPreviewConfiguration?
        return project.scenarios.map { scenario in
            guard let config = configuration?.configuration(scenarioID: scenario.id, kind: .airflowPreview),
                case .airflowPreview(let p) = config.payload,
                let request = try? AnalysisInputResolver(registry: registry).request(
                    project: project, scenarioID: scenario.id, method: .init(kind: .airflowPreview),
                    configuration: config, additionalIssues: additionalIssues),
                let result = results.last(where: {
                    $0.identity.scenarioID == scenario.id
                        && $0.identity.inputHash == request.identity.inputHash && $0.checks.state == .passed
                        && $0.method == request.method
                }), case .airflowPreview = result.payload
            else {
                return .init(
                    scenarioID: scenario.id, name: scenario.name, result: nil,
                    reason: "缺少当前输入的有效预览；共享房间/家具修改会使相关方案过期。")
            }
            if let first = profile,
                first.profileID != p.profileID || first.profileVersion != p.profileVersion
                    || first.baseRadiusMeters != p.baseRadiusMeters
                    || first.halfAngleDegrees != p.halfAngleDegrees || first.lengthMeters != p.lengthMeters
            {
                return .init(
                    scenarioID: scenario.id, name: scenario.name, result: nil,
                    reason: "展示档案或实际扩散参数不同，不能同口径比较。")
            }
            profile = p
            return .init(scenarioID: scenario.id, name: scenario.name, result: result, reason: nil)
        }
    }
}
@MainActor
public struct PreviewComparisonView: View {
    let store: WorkspaceStore
    let additionalIssues: [ValidationIssue]
    @State private var rows: [PreviewComparisonRow] = []
    public init(store: WorkspaceStore, additionalIssues: [ValidationIssue] = []) {
        self.store = store
        self.additionalIssues = additionalIssues
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("方案定性比较").font(.headline)
            Text("比较当前输入和相同展示档案的几何关系；数量不代表舒适、满意率或节电。切换方案可分别生成预览。").font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Button(row.name) { store.selectedScenarioID = row.scenarioID }
                    if let result = row.result, case .airflowPreview(let payload) = result.payload {
                        let c = PreviewRelationCounts(payload.relations)
                        Text(
                            "相交 \(c.intersects) · 遮挡 \(c.occluded) · 范围外 \(c.outside) · 不可评价 \(c.notEvaluated)"
                        ).font(.caption)
                        Text("Run \(result.identity.runID.uuidString)").font(.caption2).foregroundStyle(
                            .secondary)
                    } else {
                        Text(row.reason ?? "不可比较").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
        }.task(
            id: ComparisonBuildInput(
                project: store.project, configuration: store.analysisConfiguration,
                results: Array(store.preview.analysis.results.values), additionalIssues: additionalIssues)
        ) {
            guard let project = store.project else {
                rows = []
                return
            }
            let configs = store.analysisConfiguration
            let results = Array(store.preview.analysis.results.values)
            let registry = store.modelRegistry
            let task = Task.detached {
                PreviewComparisonBuilder.rows(
                    project: project, configuration: configs, results: results, registry: registry,
                    additionalIssues: additionalIssues)
            }
            let built = await withTaskCancellationHandler(
                operation: { await task.value }, onCancel: { task.cancel() })
            if !Task.isCancelled { rows = built }
        }
    }
}
private struct ComparisonBuildInput: Equatable {
    let project: ProjectDocument?
    let configuration: AnalysisConfigurationStore?
    let results: [LocalAnalysisResult]
    let additionalIssues: [ValidationIssue]
}
