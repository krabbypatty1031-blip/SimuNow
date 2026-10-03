import SimuCore
import SwiftUI
import SimuSimulation

@MainActor
public struct NativeAnalysisHistoryView: View {
    let store: WorkspaceStore
    let entries: [String: ProjectPackageEntry]
    let revision: UUID
    @State private var search = ""
    @State private var currentScenarioOnly = false
    @State private var index: [NativeSavedAnalysisIndex] = []
    @State private var loadedSnapshot: ScenarioInputSnapshot?
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
                Text("运行历史").font(.headline)
                Text("历史属于保存时的方案和输入。载入前验证文件与计算依据；当前结果另行核对输入是否仍然一致。").font(.caption)
                TextField("搜索方案或运行编号", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("搜索运行历史")
                Toggle("仅当前方案", isOn: $currentScenarioOnly)
                ForEach(filteredIndex) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.presentation?.scenarioName ?? scenarioName(item.scenarioID)).font(.subheadline.bold())
                        HStack {
                            if let presentation = item.presentation {
                                Text(methodName(presentation.method))
                                Text(presentation.recordedAt, format: .dateTime.year().month().day().hour().minute())
                            } else { Text("旧记录 · 未记录时间与方法，请载入查看") }
                        }.font(.caption).foregroundStyle(.secondary)
                        Label("已加入项目 · 待核对输入与方法检查", systemImage: "doc") .font(.caption)
                        Button(loaded?.identity.runID == item.id ? "重新核对这份记录" : "载入并核对") { load(item.id) }.disabled(loading != nil)
                        DisclosureGroup("记录身份与文件详情") {
                            Text(item.id.uuidString).textSelection(.enabled)
                            Text("结果文件：\(item.resultBytes) 字节")
                            Text("展示信息不证明结果有效；载入时校验完整不可变输入与结果。写入磁盘由系统文档保存负责。")
                        }.font(.caption)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                if index.isEmpty { Text("尚无本地保存记录。启用规则预览后结果加入项目包，再通过文档保存写盘。") }
                if let loaded {
                    Text("已载入\(methodName(loaded.method.kind)) · \(loaded.checks.state == .passed ? "方法检查通过" : "方法检查未通过")")
                    Text(loaded.basis == .rulePreview ? "几何规则预览；不代表现实风速或舒适。" : "基于已采用输入的简化情景估算。").font(.caption)
                    if store.project?.scenarios.contains(where: { $0.id == loaded.identity.scenarioID }) != true {
                        Text("原方案已不存在，记录仅作为历史查看。").font(.caption)
                    }
                    Text("保存时方案：" + (index.first { $0.id == loaded.identity.runID }?.presentation?.scenarioName ?? scenarioName(loaded.identity.scenarioID))).font(.callout)
                    Label(freshnessTitle(loaded), systemImage: "clock").font(.caption)
                    historicalSummary(loaded)
                    if store.project?.scenarios.contains(where: { $0.id == loaded.identity.scenarioID }) == true {
                        Button("进入对应方案查看当前结果") {
                            store.selectedScenarioID = loaded.identity.scenarioID; store.selection = .workspace
                        }
                        Text("此处展示保存时的摘要；进入工作区后只显示与当前输入匹配的结果。").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("完整运行证据") {
                        Text(loaded.identity.runID.uuidString).textSelection(.enabled)
                        Text("输入摘要：" + loaded.identity.inputHash).textSelection(.enabled)
                        Text("方法版本：\(loaded.method.methodVersion)")
                    }.font(.caption)
                }
                if loading != nil { ProgressView("验证单份历史…") }
                if let error { Text(error).foregroundStyle(.orange) }
            }.padding()
        }.task(id: revision) {
            cancelLoad()
            index = []
            loaded = nil; loadedSnapshot = nil
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
    private var filteredIndex: [NativeSavedAnalysisIndex] {
        index.filter { item in
            (!currentScenarioOnly || item.scenarioID == store.selectedScenarioID) &&
            (search.isEmpty || (item.presentation?.scenarioName ?? scenarioName(item.scenarioID)).localizedStandardContains(search) || item.id.uuidString.localizedStandardContains(search))
        }.sorted {
            let a = $0.presentation?.recordedAt ?? .distantPast, b = $1.presentation?.recordedAt ?? .distantPast
            return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
        }
    }
    private func freshnessTitle(_ result: LocalAnalysisResult) -> String {
        if result.identity.scenarioID == store.selectedScenarioID {
            if result.method.kind == .airflowPreview, store.preview.currentResult?.identity.inputHash == result.identity.inputHash { return "与当前方案输入一致" }
            if !store.estimates.validating, let request = store.estimates.prepared[result.method.kind], request.identity.inputHash == result.identity.inputHash { return "与当前方案输入一致" }
        }
        return "历史输入 · 当前适用性需在对应方案核对"
    }
    @ViewBuilder private func historicalSummary(_ result: LocalAnalysisResult) -> some View {
        switch result.payload {
        case .airflowPreview(let payload):
            let counts = PreviewRelationCounts(payload.relations)
            Text("保存时关系条数：相交 \(counts.intersects) · 遮挡 \(counts.occluded) · 范围外 \(counts.outside) · 不可评价 \(counts.notEvaluated)").font(.callout)
            DisclosureGroup("保存时的逐座位关系") {
                ForEach(PreviewSeatAssessment.grouped(payload), id: \.seatID) { assessment in
                    Text((loadedSnapshot?.inputs.usage.seats.first { $0.id == assessment.seatID }?.name ?? "历史座位") + "：" + assessment.relations.map { $0.state.displayTitle }.joined(separator: "、")).font(.caption)
                }
                ForEach(payload.notes, id: \.self) { Text($0).font(.caption) }
            }
        case .powerEstimate(let payload):
            Text("保存时电量：" + (payload.totalEnergyKWh.map { $0.formatted() + " kWh" } ?? "待补充"))
        case .steadyHeatBalance(let payload):
            Text("保存时显热收支：" + (payload.totalSignedWatts.map { $0.formatted() + " W" } ?? "待补充"))
        }
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
                loaded = artifact.result; loadedSnapshot = artifact.request.resolvedInput.snapshot
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
