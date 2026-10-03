import SimuCore
import SimuSimulation
import SimuVisualization
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
        registry: ModelRegistry = .builtIn, additionalIssues: [ValidationIssue] = [], baselineScenarioID: UUID? = nil
    ) -> [PreviewComparisonRow] {
        let referenceID = baselineScenarioID ?? project.scenarios.first?.id
        let reference = referenceID.flatMap { configuration?.configuration(scenarioID: $0, kind: .airflowPreview) }
        let profile: AirflowPreviewConfiguration?
        if let reference, case .airflowPreview(let value) = reference.payload { profile = value } else { profile = nil }
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
                    reason: "预览假设或实际扩散参数不同，不能同口径比较。")
            }
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
            Text("比较风向与遮挡").font(.headline)
            Text("比较当前输入和相同预览假设的几何关系；数量不代表舒适、满意率或节电。切换方案可分别生成预览。").font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.name).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                        if row.scenarioID == store.baselineScenarioID { Label("基准", systemImage: "flag.fill").font(.caption) }
                        if row.scenarioID == store.selectedScenarioID { Text("当前编辑").font(.caption).foregroundStyle(.secondary) }
                    }
                    Button(row.result == nil ? "进入方案并生成预览" : "在房间中查看") {
                        store.selectedScenarioID = row.scenarioID; store.selection = .workspace
                    }
                    if let result = row.result, case .airflowPreview(let payload) = result.payload {
                        let c = PreviewRelationCounts(payload.relations)
                        Text(
                            "关系条数：相交 \(c.intersects) · 遮挡 \(c.occluded) · 范围外 \(c.outside) · 不可评价 \(c.notEvaluated)"
                        ).font(.caption)
                        DisclosureGroup("逐座位关系与输入差异") {
                            ForEach(PreviewSeatAssessment.grouped(payload), id: \.seatID) { assessment in
                                let seatName = store.project?.scenarios.first { $0.id == row.scenarioID }?.inputs.usage.seats.first { $0.id == assessment.seatID }?.name ?? "原座位"
                                Text(seatName + "：" + assessment.relations.map { $0.state.displayTitle }.joined(separator: "、")).font(.caption)
                                if let baseline = rows.first(where: { $0.scenarioID == store.baselineScenarioID })?.result,
                                   case .airflowPreview(let original) = baseline.payload {
                                    let before = Dictionary(grouping: original.relations.filter { $0.seatID == assessment.seatID }, by: { $0.sampleID?.uuidString ?? "seat-position" })
                                    let after = Dictionary(grouping: assessment.relations, by: { $0.sampleID?.uuidString ?? "seat-position" })
                                    Text(before == after ? "与基准关系一致" : before.isEmpty ? "基准没有相同身份的座位，不能逐点对应" : "此座位的关系相对基准已变化").font(.caption2).foregroundStyle(.secondary)
                                }
                                ForEach(Array(assessment.relations.enumerated()), id: \.offset) { index, relation in
                                    Text("\(relation.isPositionMarker ? "座位位置" : "关注点 \(index + 1)")：\(relation.state.displayTitle)" + (relation.hitEntityID.map { hit in
                                        " · 首次遮挡：" + (store.project?.geometry.obstacles.first { $0.id == hit }?.name ?? "原遮挡对象")
                                    } ?? "")).font(.caption2)
                                }
                            }
                            inputDifference(row.scenarioID)
                        }
                        DisclosureGroup("运行证据") { Text(result.identity.runID.uuidString).font(.caption2).textSelection(.enabled) }
                    } else {
                        Text(row.reason ?? "不可比较").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }.task(
            id: ComparisonBuildInput(
                project: store.project, configuration: store.analysisConfiguration,
                results: Array(store.preview.analysis.results.values), additionalIssues: additionalIssues,
                baselineScenarioID: store.baselineScenarioID)
        ) {
            guard let project = store.project else {
                rows = []
                return
            }
            let configs = store.analysisConfiguration
            let results = Array(store.preview.analysis.results.values)
            let registry = store.modelRegistry
            let baseline = store.baselineScenarioID
            let task = Task.detached {
                PreviewComparisonBuilder.rows(
                    project: project, configuration: configs, results: results, registry: registry,
                    additionalIssues: additionalIssues, baselineScenarioID: baseline)
            }
            let built = await withTaskCancellationHandler(
                operation: { await task.value }, onCancel: { task.cancel() })
            if !Task.isCancelled { rows = built }
        }
    }
    @ViewBuilder private func inputDifference(_ id: UUID) -> some View {
        if let project = store.project, let current = project.scenarios.first(where: { $0.id == id }),
           let baseline = project.scenarios.first(where: { $0.id == store.baselineScenarioID }) {
            if id == baseline.id { Text("比较基准；房间、门窗和家具为共享几何。").font(.caption) }
            else {
                ForEach(baseline.inputs.usage.seats.filter { original in !current.inputs.usage.seats.contains { $0.id == original.id } }, id: \.id) { seat in
                    Text("移除基准座位：" + seat.name).font(.caption)
                }
                ForEach(current.inputs.hvac, id: \.id) { device in
                    if let original = baseline.inputs.hvac.first(where: { $0.id == device.id }) {
                        Text(device.name + (device.position == original.position ? " · 位置相同" : " · 位置已改变")).font(.caption)
                        ForEach(device.ports, id: \.id) { port in
                            if let previous = original.ports.first(where: { $0.id == port.id }) {
                                let angle = AirflowDirection.angles(port.direction), before = AirflowDirection.angles(previous.direction)
                                Text("风口水平角 \(before.yaw.formatted())° → \(angle.yaw.formatted())°；俯仰角 \(before.pitch.formatted())° → \(angle.pitch.formatted())°").font(.caption)
                                if port.position != previous.position { Text("风口位置相对基准已改变。").font(.caption) }
                            } else { Text("新增风口；无对应基准身份。").font(.caption) }
                        }
                    } else { Text(device.name + " · 新增空调；无对应基准身份。").font(.caption) }
                }
                let removed = baseline.inputs.hvac.filter { original in !current.inputs.hvac.contains { $0.id == original.id } }
                ForEach(removed, id: \.id) { device in Text("移除基准空调：" + device.name).font(.caption) }
            }
        }
    }
}
private struct ComparisonBuildInput: Equatable {
    let project: ProjectDocument?
    let configuration: AnalysisConfigurationStore?
    let results: [LocalAnalysisResult]
    let additionalIssues: [ValidationIssue]
    let baselineScenarioID: UUID?
}
