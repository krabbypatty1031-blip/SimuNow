import SwiftUI
import SimuCore
import SimuSimulation
import SimuVisualization

public enum FixedPreviewComparisonBuilder {
    public static func build(project: ProjectDocument, configuration: AnalysisConfigurationStore?, baselineID: UUID,
                             candidateIDs: [UUID], entries: [String: ProjectPackageEntry]) throws -> FixedComparisonArtifact {
        let ids = [baselineID] + candidateIDs
        guard (2...3).contains(ids.count), Set(ids).count == ids.count else { throw ProjectDataError.contract("选择基准和一至两个独立候选。") }
        let index = NativeArtifactCodec().index(entries: entries, projectID: project.id)
        let evidence = try ids.map { id -> FixedEstimateEvidence in
            guard let config = configuration?.configuration(scenarioID: id, kind: .airflowPreview) else { throw ProjectDataError.contract("方案缺少已确认的展示档案。") }
            let current = try AnalysisInputResolver().request(project: project, scenarioID: id, method: .init(kind: .airflowPreview), configuration: config)
            for entry in index where entry.scenarioID == id {
                try Task.checkCancellation()
                guard let run = try? NativeArtifactCodec().load(runID: entry.id, entries: entries, projectID: project.id),
                      run.request.method == current.method, run.request.identity.inputHash == current.identity.inputHash,
                      run.result.checks.state == .passed else { continue }
                return .init(request: run.request, result: run.result, currentInputHash: current.identity.inputHash)
            }
            throw ProjectDataError.contract("所选方案没有与当前输入一致的已保存预览。请切换该方案并运行预览。")
        }
        let snapshot = try ComparisonRecordCodec.snapshotFor(evidence, decisions: ["direction"])
        return try FixedComparisonArtifacts.make(snapshot, entries: entries)
    }
}

@MainActor public struct FixedPreviewComparisonView: View {
    let store: WorkspaceStore
    let entries: [String: ProjectPackageEntry]
    let revision: UUID
    @State private var candidates: Set<UUID> = []
    @State private var record: ComparisonRecord?
    @State private var relations: [UUID: [PreviewTargetRelation]] = [:]
    @State private var saved: [ComparisonRecord] = []
    @State private var page = 0
    @State private var fileCount = 0
    @State private var parents: [NativeAnalysisArtifact] = []
    @State private var error: String?
    @State private var busy = false
    @State private var work: Task<Void, Never>?
    @State private var token = UUID()
    public init(store: WorkspaceStore, entries: [String: ProjectPackageEntry], revision: UUID) {
        self.store = store; self.entries = entries; self.revision = revision
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("保存基准与候选比较").font(.headline)
            Text("方向为明确的比较变量。每个采样点保留自己的几何关系；不将数量排成舒适分或节能率。")
                .font(.caption).foregroundStyle(.secondary)
            if let project = store.project {
                ForEach(project.scenarios.filter { $0.id != store.baselineScenarioID }, id: \.id) { scenario in
                    Toggle("候选：\(scenario.name)", isOn: Binding(get: { candidates.contains(scenario.id) }, set: {
                        if $0 { candidates.insert(scenario.id) } else { candidates.remove(scenario.id) }
                    }))
                }
            }
            Button("冻结并保存比较到项目") { build() }.disabled(busy || !(1...2).contains(candidates.count) || store.baselineScenarioID == nil)
            if busy { ProgressView("核对输入、档案和固定运行…") }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let record {
                Text("固定比较 \(record.id.uuidString.prefix(8))").font(.subheadline)
                Text("项目内的固定证据不会随编辑改变。当前输入改变后，需重新冻结比较。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(record.snapshot.incomparableReasons.enumerated()), id: \.offset) { _, reason in Text(reason.reason).font(.caption) }
                if let project = store.project, !parents.isEmpty, parents.allSatisfy({ $0.result.method.kind == .airflowPreview }) {
                    DisclosureGroup("同视角房间比较") { SynchronizedPreviewView(project: project, artifacts: parents) }
                }
                ForEach(record.snapshot.runs, id: \.runID) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.project?.scenarios.first { $0.id == run.scenarioID }?.name ?? "历史方案").font(.subheadline)
                        ForEach(Array((relations[run.runID] ?? []).enumerated()), id: \.offset) { offset, relation in
                            Text("关注点 \(relation.seatID.uuidString.prefix(6)) · 采样 \(offset + 1)：\(relation.state.displayTitle)").font(.caption)
                        }
                        Text("Run \(run.runID.uuidString) · 输入 \(run.inputHash)").font(.caption2).textSelection(.enabled)
                    }
                }
                ForEach(record.snapshot.metrics ?? [], id: \.metric) { metric in
                    if metric.metric == "qualitativePathRelations" { Text("逐点几何关系：详见各采样点固定证据").font(.caption) }
                    else { Text("\(metric.metric == "energy" ? "声明时段电量" : metric.metric == "referenceCost" ? "声明时段费用" : "工况显热需求")：\(metric.baseline?.formatted() ?? "未知") → \(metric.candidate?.formatted() ?? "未知") \(metric.unit)").font(.caption) }
                    Text(comparisonRankingTitle(metric.ranking)).font(.caption)
                }
            }
            DisclosureGroup("项目中的固定比较（\(saved.count)）") {
                ForEach(saved) { item in
                    Button("查看固定比较 \(item.id.uuidString.prefix(8))") { load(item) }
                }
                HStack {
                    Button("上一页") { page -= 1 }.disabled(page == 0 || busy)
                    Text("第 \(page + 1) 页").font(.caption)
                    Button("下一页") { page += 1 }.disabled((page + 1) * 12 >= fileCount || busy)
                }
                Text("引用损坏或未来版本的记录原样保留，不能作为有效比较。每页自动检查最多 12 份比较。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(revision)/\(page)") {
            guard let projectID = store.project?.id else { return }
            let instance = store.documentInstanceID, files = entries, offset = page * 12
            let worker = Task.detached {
                let filesToRead = FixedComparisonArtifacts.data(entries: files)
                let records = try filesToRead.dropFirst(offset).prefix(12).compactMap { id, bytes -> ComparisonRecord? in
                    try Task.checkCancellation()
                    guard let artifact = try? FixedComparisonArtifacts.load(bytes, entries: files, projectID: projectID), artifact.record.id == id else { return nil }
                    return artifact.record
                }
                return (records, filesToRead.count)
            }
            let result = try? await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, (try? store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: revision)) != nil else { return }
            saved = result?.0 ?? []; fileCount = result?.1 ?? 0
            if record == nil, let first = saved.first { load(first) }
        }
        .onDisappear { work?.cancel(); token = UUID(); busy = false }
    }
    private func build() {
        guard let project = store.project, let baseline = store.baselineScenarioID else { return }
        let instance = store.documentInstanceID, inputRevision = store.revision, files = entries, configs = store.analysisConfiguration
        let ids = candidates.sorted { $0.uuidString < $1.uuidString }
        work?.cancel(); token = UUID(); let generation = token; busy = true; error = nil
        work = Task {
            defer { if token == generation { busy = false; work = nil } }
            do {
                let worker = Task.detached {
                    let artifact = try FixedPreviewComparisonBuilder.build(project: project, configuration: configs, baselineID: baseline, candidateIDs: ids, entries: files)
                    let parents = try artifact.record.snapshot.runs.map { run in
                        try Task.checkCancellation()
                        return try NativeArtifactCodec().load(runID: run.runID, entries: files, projectID: project.id)
                    }
                    return (artifact, parents)
                }
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, generation == token, store.revision == inputRevision else { return }
                try store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: revision)
                guard let persist = store.persistComparison else { throw NativeArtifactError.unsupportedRecord }
                try persist(prepared.0)
                record = prepared.0.record; parents = prepared.1; relations = relationsFor(prepared.1)
            } catch { if !Task.isCancelled, token == generation { self.error = error.localizedDescription } }
        }
    }
    private func relationsFor(_ evidence: [NativeAnalysisArtifact]) -> [UUID: [PreviewTargetRelation]] {
        Dictionary(uniqueKeysWithValues: evidence.map { artifact in
            if case .airflowPreview(let payload) = artifact.result.payload { return (artifact.manifest.runID, payload.relations) }
            return (artifact.manifest.runID, [])
        })
    }
    private func load(_ item: ComparisonRecord) {
        let files = entries, instance = store.documentInstanceID, sideRevision = revision
        work?.cancel(); token = UUID(); let generation = token; busy = true
        work = Task {
            defer { if token == generation { busy = false; work = nil } }
            do {
                let worker = Task.detached {
                    try item.snapshot.runs.map { run in
                        try Task.checkCancellation()
                        return try NativeArtifactCodec().load(runID: run.runID, entries: files, projectID: item.snapshot.projectID)
                    }
                }
                let values = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, token == generation else { return }
                try store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: sideRevision)
                record = item; parents = values; relations = relationsFor(values)
            } catch { if !Task.isCancelled, token == generation { self.error = error.localizedDescription } }
        }
    }
}
