import SimuCore
import SimuSimulation
import SwiftUI

@MainActor
public struct AirflowPreviewPanelView: View {
    let store: WorkspaceStore
    let input: PreviewWorkspaceInput
    private let onLocate: (@MainActor (UUID) -> Void)?
    private let onRepair: (@MainActor (AnalysisIssue) -> Void)?
    @State private var draft: AirflowPreviewConfigurationDraft?
    public init(store: WorkspaceStore, input: PreviewWorkspaceInput, onLocate: (@MainActor (UUID) -> Void)? = nil, onRepair: (@MainActor (AnalysisIssue) -> Void)? = nil) {
        self.store = store
        self.input = input; self.onLocate = onLocate; self.onRepair = onRepair
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
                Button("查看并采用预览假设") { openDraft() }
                Text("先确认假设，再开放预览；未知风量、温度与功率保持未知。").font(.caption)
            }
            if preview.isPending {
                Label("输入已变化，正在更新预览；旧结果保留在历史中。", systemImage: "clock").font(.caption)
            }
            if let failure = preview.inputFailure { Text(failure).font(.caption).foregroundStyle(.orange) }
            if let readiness = preview.readiness, !readiness.blockers.isEmpty {
                DisclosureGroup("预览需修复：\(readiness.blockers.count) 项") {
                    ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { _, issue in
                        Text(issue.message).font(.caption)
                        if let onRepair, issue.fieldPath != "/analysis/configuration" { Button("定位并修复") { onRepair(issue) } }
                    }
                }
            }
            if let readiness = preview.readiness {
                let warnings = readiness.warnings.filter { !$0.code.hasPrefix("not_used.") }
                if !warnings.isEmpty {
                    DisclosureGroup("方法说明与当前警告 · \(warnings.count)") {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, issue in Text(issue.message).font(.caption).foregroundStyle(.secondary) }
                    }
                }
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
                    "风口与关注点关系条数：相交 \(counts.intersects) · 遮挡 \(counts.occluded) · 范围外 \(counts.outside) · 不可评价 \(counts.notEvaluated)"
                ).font(.caption)
                Text("\(PreviewSeatAssessment.grouped(payload).count) 个座位；每条关系对应一个关注点与规则，以上条数不是座位满意率。").font(.caption).foregroundStyle(.secondary)
                EditorDisclosure(title: "关注点与遮挡原因", initiallyExpanded: true) {
                    ForEach(PreviewSeatAssessment.grouped(payload), id: \.seatID) { seat in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                (input.project?.scenarios.first { $0.id == input.scenarioID }?.inputs.usage
                                    .seats.first { $0.id == seat.seatID }?.name ?? seat.seatID.uuidString)
                                    + (seat.counts.isMixed ? " · 混合关系" : "")
                            ).font(.subheadline)
                            if let onLocate { Button("在房间中定位座位") { onLocate(seat.seatID) } }
                            ForEach(Array(seat.relations.enumerated()), id: \.offset) { index, relation in
                                Text(
                                    "\(relation.isPositionMarker ? "座位位置标记（非身体/呼吸高度）" : "采样点 \(index+1)")：\(relation.state.displayTitle)"
                                ).font(.caption)
                                if let onLocate, let sampleID = relation.sampleID { Button("定位采样点") { onLocate(sampleID) }.font(.caption) }
                                DisclosureGroup("规则依据") {
                                    Text("\(relation.ruleID) · \(payload.profileID) v\(payload.profileVersion)").font(.caption2).textSelection(.enabled)
                                }
                                if let hit = relation.hitEntityID {
                                    Text(
                                        "首次遮挡：\(input.project?.geometry.obstacles.first {$0.id == hit}?.name ?? hit.uuidString)"
                                    ).font(.caption)
                                    if let onLocate { Button("定位遮挡对象") { onLocate(hit) }.font(.caption) }
                                }
                                if let reason = relation.missingReason { Text(reason.reason).font(.caption) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                DisclosureGroup("方法边界与运行证据") {
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
        Button("预览假设") { openDraft() }
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
            EditorForm {
                Text("通用锥形规则第 1 版：内部展示假设，未按设备或实测校准。路径到第一次墙/家具接触即停止；不模拟绕流。其他已采用参数及来源会保留。")
                    .fixedSize(horizontal: false, vertical: true)
                EditorTextField(title: "出风口附近的展示半径（m）", text: $draft.radiusText)
                Text("半径决定锥形示意的起始粗细；与设备实测风口尺寸无关。").font(.caption).foregroundStyle(.secondary)
                EditorTextField(title: "示意扩散半角（°，1–45）", text: $draft.angleText)
                ConeAssumptionPreview(angle: draft.angleText, radius: draft.radiusText)
                Picker("预览密度", selection: $draft.pathCount) {
                    Text("低 · 16 条").tag(16)
                    Text("中 · 32 条").tag(32)
                    Text("高 · 64 条").tag(64)
                    if ![16, 32, 64].contains(draft.pathCount) {
                        Text("已有 · \(draft.pathCount) 条").tag(draft.pathCount)
                    }
                }
                DisclosureGroup("高级：固定路径排列") {
                    EditorTextField(title: "路径排列编号", text: $draft.seedText)
                    Text("同一编号和输入会重现同一组示意路径，不代表校准数据。").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("明确采用上述展示假设", isOn: $accepted)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("气流预览假设").toolbar {
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
            .modifier(EditorSheetSize())
        }
    }
}

private struct ConeAssumptionPreview: View {
    let angle: String
    let radius: String
    var body: some View {
        if let value = Double(angle), value.isFinite, (1...45).contains(value),
           let base = Double(radius), base.isFinite, base > 0 {
            VStack(alignment: .leading, spacing: 5) {
            Canvas { context, size in
                let endRadius = base + tan(value * .pi / 180) * 2
                let scale = min((size.width - 48) / 2, (size.height - 16) / (2 * endRadius))
                let center = CGPoint(x: 24, y: size.height / 2)
                let cone = Path { path in
                    path.move(to: .init(x: center.x, y: center.y - base * scale))
                    path.addLine(to: .init(x: center.x + 2 * scale, y: center.y - endRadius * scale))
                    path.addLine(to: .init(x: center.x + 2 * scale, y: center.y + endRadius * scale))
                    path.addLine(to: .init(x: center.x, y: center.y + base * scale)); path.closeSubpath()
                }
                context.fill(cone, with: .color(Color.accentColor.opacity(0.15)))
                context.stroke(cone, with: .color(.accentColor), lineWidth: 1.5)
            }.frame(height: 100).accessibilityHidden(true)
            Text("2 m 长度参照 · 起始半径 \(base.formatted()) m · 半角 \(value.formatted())°；示意随参数缩放，未按设备校准。").font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
