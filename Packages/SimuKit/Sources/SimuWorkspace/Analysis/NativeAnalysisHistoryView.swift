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
    public init(store: WorkspaceStore, entries: [String: ProjectPackageEntry], revision: UUID) {
        self.store = store
        self.entries = entries
        self.revision = revision
    }
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("本地规则运行与项目附件").font(.headline)
                Text("协调器最多驻留 12 份 / 24 MiB 编码载荷预算（不是进程 RAM 上限）；历史文件保留在项目包，需要时逐份验证载入。计算、方法检查、输入新鲜度与保存独立。").font(.caption)
                ForEach(index) { item in
                    Button("载入 Run \(item.id.uuidString) · \(item.resultBytes) bytes") { load(item.id) }
                        .disabled(loading != nil)
                }
                if index.isEmpty { Text("尚无本地保存记录。启用规则预览后结果加入项目包，再通过文档保存写盘。") }
                if let loaded {
                    Text(
                        "载入 \(loaded.identity.runID.uuidString) · \(loaded.basis.rawValue) · checks \(loaded.checks.state.rawValue)"
                    )
                    Text("此记录始终属于原方案和 inputHash；不是实时输入替代。当前图层另行核对输入。").font(.caption)
                    if case .airflowPreview(let payload) = loaded.payload {
                        ForEach(payload.notes, id: \.self) { Text($0).font(.caption) }
                    }
                }
                if loading != nil { ProgressView("验证单份历史…") }
                if let error { Text(error).foregroundStyle(.orange) }
            }.padding()
        }.task(id: revision) {
            guard let projectID = store.project?.id else { return }
            let entries = entries
            let registry = store.modelRegistry
            let task = Task.detached {
                NativeArtifactCodec(registry: registry).index(entries: entries, projectID: projectID)
            }
            let value = await task.value
            if !Task.isCancelled { index = value }
        }
    }
    private func load(_ id: UUID) {
        guard let projectID = store.project?.id else { return }
        loading = id
        error = nil
        let entries = entries
        let registry = store.modelRegistry
        Task {
            defer { loading = nil }
            do {
                let task = Task.detached {
                    try NativeArtifactCodec(registry: registry).load(
                        runID: id, entries: entries, projectID: projectID)
                }
                let artifact = try await task.value
                guard store.project?.id == projectID else { return }
                loaded = artifact.result
                store.preview.analysis.restore([artifact])
            } catch { self.error = "历史未作为有效结果载入，原文件保留：\(error)" }
        }
    }
}
