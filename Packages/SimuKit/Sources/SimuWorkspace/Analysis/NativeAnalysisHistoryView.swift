import SimuCore
import SwiftUI

@MainActor
public struct NativeAnalysisHistoryView: View {
    let store: WorkspaceStore
    let entries: [String: ProjectPackageEntry]
    let revision: UUID
    @State private var index: [NativeSavedAnalysisIndex] = []
    @State private var loaded: LocalAnalysisResult?
    @State private var loading: UUID?
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var generation: UInt64 = 0
    public init(store: WorkspaceStore, entries: [String: ProjectPackageEntry], revision: UUID) {
        self.store = store
        self.entries = entries
        self.revision = revision
    }
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("本地规则运行与项目附件").font(.headline)
                Text("历史属于保存时的方案和输入。载入前验证文件与计算依据；当前结果另行核对输入是否仍然一致。").font(.caption)
                ForEach(index) { item in
                    VStack(alignment: .leading) {
                        Button("载入记录 · \(scenarioName(item.scenarioID)) · \(item.id.uuidString.prefix(8))") { load(item.id) }
                            .disabled(loading != nil)
                        DisclosureGroup("记录身份与文件大小") {
                            Text(item.id.uuidString).textSelection(.enabled)
                            Text("结果文件：\(item.resultBytes) 字节")
                        }.font(.caption)
                    }
                }
                if index.isEmpty { Text("尚无本地保存记录。启用规则预览后结果加入项目包，再通过文档保存写盘。") }
                if let loaded {
                    Text("已载入\(methodName(loaded.method.kind)) · \(loaded.checks.state == .passed ? "方法检查通过" : "方法检查未通过")")
                    Text(loaded.basis == .rulePreview ? "几何规则预览；不代表现实风速或舒适。" : "基于已采用输入的简化情景估算。").font(.caption)
                    if store.project?.scenarios.contains(where: { $0.id == loaded.identity.scenarioID }) != true {
                        Text("原方案已不存在，记录仅作为历史查看。").font(.caption)
                    }
                    if case .airflowPreview(let payload) = loaded.payload {
                        ForEach(payload.notes, id: \.self) { Text($0).font(.caption) }
                    }
                }
                if loading != nil { ProgressView("验证单份历史…") }
                if let error { Text(error).foregroundStyle(.orange) }
            }.padding()
        }.task(id: revision) {
            cancelLoad()
            index = []
            loaded = nil
            error = nil
            guard let projectID = store.project?.id else { return }
            let instance = store.documentInstanceID
            let entries = entries
            let registry = store.modelRegistry
            let task = Task.detached {
                if Task.isCancelled { return [NativeSavedAnalysisIndex]() }
                return NativeArtifactCodec(registry: registry).index(entries: entries, projectID: projectID)
            }
            let value = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            do {
                try store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: revision)
                index = value
            } catch { /* A replacement document gets its own history task. */ }
        }
        .onDisappear { cancelLoad() }
    }
    private func load(_ id: UUID) {
        guard let projectID = store.project?.id else { return }
        cancelLoad()
        let token = generation
        let instance = store.documentInstanceID
        loading = id
        error = nil
        let entries = entries
        let registry = store.modelRegistry
        loadTask = Task {
            defer { if generation == token { loading = nil; loadTask = nil } }
            do {
                let task = Task.detached {
                    try Task.checkCancellation()
                    return try NativeArtifactCodec(registry: registry).load(
                        runID: id, entries: entries, projectID: projectID)
                }
                let artifact = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                try Task.checkCancellation()
                guard generation == token, store.project?.id == projectID else { return }
                try store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: revision)
                loaded = artifact.result
                guard store.project?.scenarios.contains(where: { $0.id == artifact.manifest.scenarioID }) == true else { return }
                switch artifact.result.method.kind {
                case .airflowPreview: store.preview.analysis.restore([artifact])
                case .powerEstimate: store.estimates.power.restore([artifact])
                case .steadyHeatBalance: store.estimates.heat.restore([artifact])
                }
            } catch is CancellationError { } catch {
                guard generation == token else { return }
                self.error = "历史未作为有效结果载入，原文件保留：\(error.localizedDescription)"
            }
        }
    }
    private func cancelLoad() {
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        loading = nil
    }
    private func scenarioName(_ id: UUID) -> String {
        store.project?.scenarios.first(where: { $0.id == id })?.name ?? "已删除的方案"
    }
    private func methodName(_ kind: AnalysisKind) -> String {
        switch kind {
        case .airflowPreview: "气流方向预览"
        case .powerEstimate: "电量情景"
        case .steadyHeatBalance: "显热情景"
        }
    }
}
