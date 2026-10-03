import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import SimuCore
import SimuSimulation
import SimuReporting

private struct ReportPDF: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }.suggestedFileName { _ in "SimuNow-分析建议.pdf" }
    }
}
private struct ReportJSON: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName { _ in "SimuNow-匿名证据.json" }
    }
}
private struct ReportExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json, .pdf] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor public struct LocalReportView: View {
    let store: WorkspaceStore
    let entries: [String: ProjectPackageEntry]
    let revision: UUID
    @State private var index: [NativeSavedAnalysisIndex] = []
    @State private var selected: Set<UUID> = []
    @State private var comparisons: [ComparisonRecord] = []
    @State private var comparisonID: UUID?
    @State private var comparisonPage = 0
    @State private var comparisonFileCount = 0
    @State private var snapshot: LocalReportSnapshot?
    @State private var text = ""
    @State private var json: Data?
    @State private var pdf: Data?
    @State private var error: String?
    @State private var busy = false
    @State private var generation = UUID()
    @State private var work: Task<Void, Never>?
    @State private var exportDocument: ReportExportDocument?
    @State private var exportType: UTType = .plainText
    @State private var exporting = false
    public init(store: WorkspaceStore, entries: [String: ProjectPackageEntry], revision: UUID) {
        self.store = store; self.entries = entries; self.revision = revision
    }
    public var body: some View {
        Form {
            Section("选择固定证据") {
                Text("默认分享匿名摘要：隐藏项目、方案、关注点名称、完整几何及私有来源。完整项目请通过文档另存或导出。")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(index) { item in
                    Toggle("\(scenarioName(item.scenarioID)) · Run \(item.id.uuidString.prefix(8))", isOn: Binding(
                        get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }))
                }
                Picker("包含固定比较", selection: $comparisonID) {
                    Text("不包含比较").tag(Optional<UUID>.none)
                    ForEach(comparisons) { item in Text("比较 \(item.id.uuidString.prefix(8))").tag(Optional(item.id)) }
                }.onChange(of: comparisonID) { _, id in
                    if let item = comparisons.first(where: { $0.id == id }) { selected.formUnion(item.snapshot.runs.map(\.runID)) }
                }
                HStack {
                    Button("上一页比较") { comparisonID = nil; comparisonPage -= 1 }.disabled(comparisonPage == 0 || busy)
                    Button("下一页比较") { comparisonID = nil; comparisonPage += 1 }.disabled((comparisonPage + 1) * 12 >= comparisonFileCount || busy)
                }
                if index.isEmpty { Text("先运行预览并保存项目。已保存的固定运行会出现在这里。") }
                Button("冻结证据并预览匿名摘要") { build() }.disabled(busy || selected.isEmpty || selected.count > 12)
                if selected.count > 12 { Text("一次最多分享 12 份运行。") }
                if busy { ProgressView("核对固定证据并生成报告…") }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            if let snapshot {
                Section("分享前预览") {
                    Text(text).font(.callout).textSelection(.enabled)
                    Text("冻结后编辑项目不会改变此摘要。若当前输入已变化，请重新生成以分享当前建议。")
                        .font(.caption).foregroundStyle(.secondary)
                    ShareLink(item: text) { Label("分享文字建议", systemImage: "square.and.arrow.up") }
                    if let json { ShareLink(item: ReportJSON(data: json), preview: SharePreview("SimuNow 匿名证据")) { Label("分享 JSON 证据", systemImage: "doc.badge.arrow.up") } }
                    if let pdf { ShareLink(item: ReportPDF(data: pdf), preview: SharePreview("SimuNow 分析建议")) { Label("分享 PDF", systemImage: "doc.richtext") } }
                    Menu("保存报告文件") {
                        Button("UTF-8 文字") { save(Data(text.utf8), type: .plainText) }
                        if let json { Button("JSON 证据") { save(json, type: .json) } }
                        if let pdf { Button("PDF") { save(pdf, type: .pdf) } }
                    }
                    Text("报告 ID：\(snapshot.reportID)").font(.caption)
                }
            }
            Section("数据与许可") {
                LabeledContent("应用版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"))")
                Text("房间、测量与照片保存在本地。只有你发起系统分享或文件导出时，所选内容才交给对应目标。本地规则和简化估算无需账号、网络或外部运行时。")
                Text("SwiftUI、RealityKit、CoreText 与 RoomPlan 是 Apple 系统框架。本地规则与研究模型为 SimuNow 实现，适用范围与未验收项见各自证据。")
            }
        }.formStyle(.grouped)
        .task(id: "\(revision)/\(comparisonPage)") {
            guard let projectID = store.project?.id else { index = []; return }
            let instance = store.documentInstanceID, files = entries, offset = comparisonPage * 12
            let worker = Task.detached {
                let index = NativeArtifactCodec().index(entries: files, projectID: projectID)
                let comparisonFiles = FixedComparisonArtifacts.data(entries: files)
                let records = try comparisonFiles.dropFirst(offset).prefix(12).compactMap { _, data in
                    try Task.checkCancellation()
                    return try? FixedComparisonArtifacts.load(data, entries: files, projectID: projectID).record
                }
                return (index, records, comparisonFiles.count)
            }
            let loaded = try? await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, (try? store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: revision)) != nil else { return }
            index = loaded?.0 ?? []; comparisons = loaded?.1 ?? []; comparisonFileCount = loaded?.2 ?? 0
            selected.formIntersection(Set(index.map(\.id)))
            if !comparisons.contains(where: { $0.id == comparisonID }) { comparisonID = nil }
        }
        .onDisappear { work?.cancel(); generation = UUID(); busy = false }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType, defaultFilename: "SimuNow-匿名分析") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
            exportDocument = nil
        }
    }
    private func scenarioName(_ id: UUID) -> String { store.project?.scenarios.first { $0.id == id }?.name ?? "已删除的方案（历史）" }
    private func save(_ data: Data, type: UTType) { exportDocument = .init(data: data); exportType = type; exporting = true }
    private func build() {
        guard let project = store.project else { return }
        let instance = store.documentInstanceID, sideRevision = revision, inputRevision = store.revision
        let comparison = comparisons.first { $0.id == comparisonID }?.snapshot
        let files = entries, ids = selected.sorted { $0.uuidString < $1.uuidString }, configs = store.analysisConfiguration
        work?.cancel(); generation = UUID(); let token = generation; busy = true; error = nil
        work = Task {
            defer { if generation == token { busy = false; work = nil } }
            do {
                let worker = Task.detached {
                    let evidence = try ids.map { id -> FixedReportEvidence in
                        try Task.checkCancellation()
                        let a = try NativeArtifactCodec().load(runID: id, entries: files, projectID: project.id)
                        let current = configs?.configuration(scenarioID: a.request.identity.scenarioID, kind: a.request.method.kind).flatMap { config in
                            try? AnalysisInputResolver().request(project: project, scenarioID: a.request.identity.scenarioID, method: a.request.method, configuration: config)
                        }
                        let cards = a.request.method.kind == .airflowPreview && current?.identity.inputHash == a.result.identity.inputHash
                            ? try PreviewRecommendationRules.suggestions(request: a.request, result: a.result, currentInputHash: a.result.identity.inputHash) : []
                        var cost: CostEvaluationRecord?
                        let fixedReference = comparison?.runs.first { $0.runID == id }
                        if let hash = fixedReference?.evaluationHash {
                            // Historical comparisons keep their original tariff evidence, including orphaned scenarios.
                            cost = try NativeCostEvaluationCodec.load(hash: hash, parent: a, entries: files)
                        } else if fixedReference == nil, case .powerEstimate(let payload) = a.result.payload,
                                  let scenario = project.scenarios.first(where: { $0.id == a.result.identity.scenarioID }) {
                            let configuration = CostEvaluationConfiguration(requestedWindows: payload.requestedWindows, currency: scenario.evaluation.cost.currency,
                                tariffs: scenario.evaluation.cost.tariffs.map { .init(startMinute: $0.startMinute, endMinute: $0.endMinute, rate: $0.rate) })
                            let hash = try AnalysisHasher().evaluationHash(identity: a.result.identity, evaluationConfiguration: JSONTreeCoding.encode(configuration))
                            cost = try? NativeCostEvaluationCodec.load(hash: hash, parent: a, entries: files)
                        }
                        return .init(request: a.request, result: a.result, currentInputHash: current?.identity.inputHash, suggestions: cards, cost: cost)
                    }
                    let summary = try LocalReportBuilder.build(evidence, comparison: comparison)
                    let text = try LocalReportExporter.export(summary, format: .plainText)
                    let json = try LocalReportExporter.export(summary, format: .evidenceSummary)
                    var pdf: Data?, pdfFailure: String?
                    do { pdf = try LocalReportExporter.export(summary, format: .pdf).data }
                    catch { pdfFailure = "PDF 生成失败；文字与 JSON 仍可分享：\(error.localizedDescription)" }
                    try Task.checkCancellation()
                    return (summary, text.data, json.data, pdf, pdfFailure)
                }
                let built = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, generation == token, store.revision == inputRevision else { return }
                try store.validateNativeDocumentContext(instanceID: instance, sidefileRevision: sideRevision)
                snapshot = built.0; text = String(decoding: built.1, as: UTF8.self); json = built.2; pdf = built.3; error = built.4
            } catch { if !Task.isCancelled, generation == token { self.error = error.localizedDescription } }
        }
    }
}
