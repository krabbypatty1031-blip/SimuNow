import SimuCore
import SimuSimulation
import SwiftUI

@MainActor
public struct AirflowPreviewPanelView: View {
    let store: WorkspaceStore
    let input: PreviewWorkspaceInput
    @State private var draft: AirflowPreviewConfigurationDraft?
    public init(store: WorkspaceStore, input: PreviewWorkspaceInput) {
        self.store = store
        self.input = input
    }
    private var configuration: AirflowPreviewConfiguration? {
        if case .airflowPreview(let v) = input.configuration?.payload { return v }
        return nil
    }
    private func persist(_ artifact: NativeAnalysisArtifact) throws {
        guard let write = store.persistNativeAnalysis else { throw NativeArtifactError.unsupportedRecord }
        try write(artifact)
    }
    public var body: some View {
        @Bindable var preview = store.preview
        VStack(alignment: .leading, spacing: 10) {
            Label("本地风向与遮挡预览", systemImage: "wind").font(.headline)
            Text("通用锥形规则只描述假设路径与家具遮挡，不计算现实风速、温度或舒适。显示密度不代表设备风档。").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let config = configuration {
                Text(
                    "已采用展示假设：起始半径 \(config.baseRadiusMeters.formatted()) m · 半角 \(config.halfAngleDegrees.formatted())° · \(config.lengthMeters.map { $0.formatted()+" m" } ?? "房间对角线范围") · v\(config.profileVersion)"
                ).font(.caption)
                ViewThatFits(in: .horizontal) {
                    HStack { controls }
                    VStack(alignment: .leading) { controls }
                }
            } else {
                Button("查看并采用展示档案") { openDraft() }
                Text("先确认假设，再开放预览；未知风量、温度与功率保持未知。").font(.caption)
            }
            if preview.isPending {
                Label("输入已变化，250 ms 防抖后更新；旧结果保留为历史。", systemImage: "clock").font(.caption)
            }
            if let failure = preview.inputFailure { Text(failure).font(.caption).foregroundStyle(.orange) }
            if let readiness = preview.readiness, !readiness.blockers.isEmpty {
                DisclosureGroup("预览需修复：\(readiness.blockers.count) 项") {
                    ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { _, issue in
                        Text(issue.message).font(.caption)
                    }
                }
            }
            if let readiness = preview.readiness {
                ForEach(
                    Array(readiness.warnings.filter { !$0.code.hasPrefix("not_used.") }.enumerated()),
                    id: \.offset
                ) { _, issue in Text(issue.message).font(.caption).foregroundStyle(.secondary) }
            }
            if let stage = preview.currentStage {
                Text("任务：\(stageTitle(stage))").font(.caption)
            }
            if let failure = preview.currentFailure {
                Text(failure.reason).font(.caption).foregroundStyle(.orange)
            }
            if let result = preview.currentResult, case .airflowPreview(let payload) = result.payload {
                Text("方法检查：\(result.checks.state == .passed ? "通过" : "未通过") · 依据：几何规则 · 当前输入").font(.caption)
                Text(persistenceTitle(preview.analysis.persistence[result.identity.runID] ?? .notSaved)).font(
                    .caption
                ).foregroundStyle(.secondary)
                let counts = PreviewRelationCounts(payload.relations)
                Text(
                    "几何关系数量：相交 \(counts.intersects) · 遮挡 \(counts.occluded) · 范围外 \(counts.outside) · 不可评价 \(counts.notEvaluated)"
                ).font(.caption)
                DisclosureGroup("关注点关系与规则依据") {
                    ForEach(PreviewSeatAssessment.grouped(payload), id: \.seatID) { seat in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                (input.project?.scenarios.first { $0.id == input.scenarioID }?.inputs.usage
                                    .seats.first { $0.id == seat.seatID }?.name ?? seat.seatID.uuidString)
                                    + (seat.counts.isMixed ? " · mixed / 混合关系" : "")
                            ).font(.subheadline)
                            ForEach(Array(seat.relations.enumerated()), id: \.offset) { index, relation in
                                Text(
                                    "\(relation.isPositionMarker ? "座位位置标记（非身体/呼吸高度）" : "采样点 \(index+1)")：\(relation.state.displayTitle)"
                                ).font(.caption)
                                Text("\(relation.ruleID) · \(payload.profileID) v\(payload.profileVersion)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let hit = relation.hitEntityID {
                                    Text(
                                        "首次遮挡：\(input.project?.geometry.obstacles.first {$0.id == hit}?.name ?? hit.uuidString)"
                                    ).font(.caption)
                                }
                                if let reason = relation.missingReason { Text(reason.reason).font(.caption) }
                            }
                        }.padding(.vertical, 4)
                    }
                    ForEach(payload.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Text("Run \(result.identity.runID.uuidString) · inputHash \(result.identity.inputHash)")
                        .font(.caption2).textSelection(.enabled)
                }
            }
        }
        .sheet(item: $draft) { draft in
            AirflowPreviewConfigurationEditor(draft: draft) { edited in
                let configurations = try edited.applying(
                    currentProject: store.project, currentScenarioID: store.selectedScenarioID,
                    currentStore: store.analysisConfiguration)
                try store.updateAnalysisConfiguration(configurations, actionName: "采用气流展示假设")
                let input = PreviewWorkspaceInput(
                    project: store.project, scenarioID: store.selectedScenarioID,
                    configuration: configurations.configuration(
                        scenarioID: edited.scenarioID, kind: .airflowPreview),
                    additionalIssues: self.input.additionalIssues)
                store.preview.setEnabled(true, input: input, registry: store.modelRegistry, persist: persist)
            }
        }
    }
    private func openDraft() {
        guard let project = store.project, let id = store.selectedScenarioID else { return }
        draft = .init(project: project, scenarioID: id, store: store.analysisConfiguration)
    }
    @ViewBuilder private var controls: some View {
        Toggle(
            "启用预览",
            isOn: Binding(
                get: { store.preview.enabled },
                set: {
                    store.preview.setEnabled(
                        $0, input: input, registry: store.modelRegistry, persist: persist)
                }))
        Toggle("显示路径", isOn: Binding(get: { store.preview.showPaths }, set: { store.preview.showPaths = $0 }))
            .disabled(!store.preview.enabled)
        Button("展示档案") { openDraft() }
        Button("重新预览") { store.preview.retry(registry: store.modelRegistry, persist: persist) }.disabled(
            !store.preview.enabled)
        Button("取消") { store.preview.cancel() }.disabled(
            !store.preview.enabled
                || store.preview.analysis.stage?.isTerminal == true && !store.preview.isPending)
    }
    private func stageTitle(_ stage: LocalAnalysisStage) -> String {
        switch stage {
        case .accepted: "已接受"
        case .validating: "验证输入"
        case .running, .progress: "计算规则"
        case .checking: "方法检查"
        case .completed: "计算完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }
    private func persistenceTitle(_ state: AnalysisPersistenceState) -> String {
        switch state {
        case .saved: "结果已加入项目；写入磁盘由文档保存负责。"
        case .notSaved: "结果未加入项目。"
        case .failed(let reason): "计算已完成，结果未保存：\(reason)"
        }
    }
}
extension PreviewRelationState {
    public var displayTitle: String {
        switch self {
        case .intersectsAssumedPath: "与假设路径相交"
        case .occluded: "路径被家具遮挡"
        case .outsideAssumedPath: "未在此假设路径范围内"
        case .notEvaluated: "不可评价"
        }
    }
}
private struct AirflowPreviewConfigurationEditor: View {
    let onApply: @MainActor (AirflowPreviewConfigurationDraft) throws -> Void
    @State private var draft: AirflowPreviewConfigurationDraft
    @State private var accepted = false
    @State private var error: String?
    @SwiftUI.Environment(\.dismiss) private var dismiss
    init(
        draft: AirflowPreviewConfigurationDraft,
        onApply: @escaping @MainActor (AirflowPreviewConfigurationDraft) throws -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onApply = onApply
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("genericCone v1：内部展示假设，未按设备或实测校准。路径到第一次墙/家具接触即停止；不模拟绕流。已有范围、步数、强度阈值与来源会保留。")
                TextField("起始半径 / m", text: $draft.radiusText)
                TextField("扩散半角 / °（1…45）", text: $draft.angleText)
                Picker("预览密度", selection: $draft.pathCount) {
                    Text("低 · 16 条").tag(16)
                    Text("中 · 32 条").tag(32)
                    Text("高 · 64 条").tag(64)
                    if ![16, 32, 64].contains(draft.pathCount) {
                        Text("已有 · \(draft.pathCount) 条").tag(draft.pathCount)
                    }
                }
                TextField("确定性 seed / UInt32", text: $draft.seedText)
                Toggle("明确采用上述展示假设", isOn: $accepted)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("气流展示档案").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("采用并预览") {
                        do {
                            try onApply(draft)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!accepted)
                }
            }
            #if os(macOS)
                .frame(minWidth: 480, minHeight: 400)
            #endif
        }
    }
}
