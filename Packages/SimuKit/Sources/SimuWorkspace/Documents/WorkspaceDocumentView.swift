import SwiftUI
import SimuCore
import SimuSimulation
import SimuVisualization
import UniformTypeIdentifiers

/// Native document binding is the persisted authority. Each window has its own
/// workflow store; all commits publish complete values back to this binding.
@MainActor
public struct WorkspaceDocumentView: View {
    @Binding private var document: SimuNowDocument
    @State private var store: WorkspaceStore
    @State private var importingJSON = false
    @State private var importingWeather = false
    @State private var weatherScenarioID: UUID?
    @State private var weatherRevision: UInt64?
    @State private var migratingURL: URL?
    @State private var busy = false
    @State private var notice: String?
    private let rendererCapability: RendererCapabilities
    private let io = ProjectPackageIO()
    #if os(macOS)
    @SwiftUI.Environment(\.newDocument) private var newDocument
    #else
    @State private var importedDocument: SimuNowDocument?
    @State private var exportingImport = false
    @State private var editingImport = false
    @State private var pendingExport = false
    @State private var importNotes: [String] = []
    #endif

    public init(document: Binding<SimuNowDocument>, localAnalysisClient: any LocalAnalysisSubmitting = LocalAnalysisClient.production(), rendererCapability: RendererCapabilities = .current) {
        _document = document
        self.rendererCapability = rendererCapability
        let value = document.wrappedValue
        let store = WorkspaceStore(localAnalysisClient: localAnalysisClient)
        store.load(value.project, baselineScenarioID: value.metadata.baselineScenarioID,
                   templateID: value.metadata.templateID, templateVersion: value.metadata.templateVersion,
                   analysisConfiguration: value.analysisConfigurationData == nil ? nil : try? value.analysisConfigurationStore())
        _store = State(initialValue: store)
    }
    public var body: some View {
        WorkspaceView(store: store, nativeEntries: document.preservedEntries, nativeSidefileRevision: document.nativeSidefileRevision, rendererCapability: rendererCapability, packageIssues: document.integrityReport.issues.filter {
            $0.code.hasPrefix("weather_asset_") || ["baseline_reference", "package_metadata", "project_contract"].contains($0.code)
        }, onImportJSON: { importingJSON = true }, onImportWeather: { id in
            weatherScenarioID = id; weatherRevision = store.revision; importingWeather = true
        })
        .overlay(alignment: .bottom) {
            if busy { ProgressView("正在读取文件…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding() }
        }
        .onAppear { connect() }
        .onChange(of: document.project) { _, _ in synchronizeExternalChanges() }
        .onChange(of: document.analysisConfigurationData) { _, _ in synchronizeExternalChanges() }
        .onChange(of: document.metadata) { _, _ in synchronizeExternalChanges() }
        .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importJSON(url, migrating: false)
            case .failure(let error): store.presentedError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importingWeather, allowedContentTypes: [.data, .text]) { result in
            switch result {
            case .success(let url): importWeather(url)
            case .failure(let error): store.presentedError = error.localizedDescription
            }
        }
        .confirmationDialog("迁移旧版 v1 草稿为新项目？", isPresented: Binding(
            get: { migratingURL != nil }, set: { if !$0 { migratingURL = nil } }), titleVisibility: .visible) {
            Button("迁移为新项目") { if let url = migratingURL { migratingURL = nil; importJSON(url, migrating: true) } }
            Button("取消", role: .cancel) { migratingURL = nil }
        } message: { Text("原 JSON 不会改写。v1 缺少的模型参数保持未知，需要继续补充。") }
        .alert("文件操作", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("好", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        #if os(iOS)
        .sheet(isPresented: $editingImport, onDismiss: {
            if pendingExport { pendingExport = false; exportingImport = true }
        }) {
            if let importedDocument {
                ImportedProjectEditorView(initialDocument: importedDocument, notes: importNotes, localAnalysisClient: store.localAnalysisClient) { edited in
                    self.importedDocument = edited
                    pendingExport = true; editingImport = false
                }
            }
        }
        .fileExporter(isPresented: $exportingImport, document: importedDocument,
                      contentType: .simuNowProject, defaultFilename: importedDocument?.project.name ?? "导入项目") { result in
            switch result {
            case .success: notice = "已导出新项目包。请返回文档浏览器打开该 .simunow 文件；当前项目保持独立。"
            case .failure(let error): store.presentedError = error.localizedDescription
            }
        }
        #endif
    }
    private func connect() {
        // Capture the native binding alone, avoiding store -> callback -> view -> store.
        let documentBinding = $document
        store.persistNativeAnalysis = { artifact in
            documentBinding.wrappedValue = try documentBinding.wrappedValue.appendingNativeAnalysis(artifact,expectedProjectID: artifact.manifest.projectID)
        }
        store.persistCostEvaluation = { artifact in
            documentBinding.wrappedValue = try documentBinding.wrappedValue.appendingCostEvaluation(artifact,expectedProjectID:artifact.record.projectID)
        }
        store.validateDocumentChange = { state in
            _ = try documentBinding.wrappedValue.applyingWorkspaceState(state)
        }
        store.onDocumentChange = { state in
            // The synchronous preflight immediately precedes this callback. No asynchronous writer intervenes.
            if let next = try? documentBinding.wrappedValue.applyingWorkspaceState(state) { documentBinding.wrappedValue = next }
        }
    }
    private func synchronizeExternalChanges() {
        guard store.project != document.project || store.baselineScenarioID != document.metadata.baselineScenarioID ||
                store.templateID != document.metadata.templateID || store.templateVersion != document.metadata.templateVersion ||
                store.analysisConfiguration != (document.analysisConfigurationData == nil ? nil : try? document.analysisConfigurationStore()) else { return }
        let selection = store.selectedScenarioID
        store.load(document.project, baselineScenarioID: document.metadata.baselineScenarioID,
                   templateID: document.metadata.templateID, templateVersion: document.metadata.templateVersion,
                   analysisConfiguration: document.analysisConfigurationData == nil ? nil : try? document.analysisConfigurationStore())
        if document.project.scenarios.contains(where: { $0.id == selection }) { store.selectedScenarioID = selection }
        notice = "文档收到外部更新，已载入最新输入。正在编辑的旧草稿仍可查看；请关闭并重新打开表单后继续修改。"
        connect()
    }
    private func importJSON(_ url: URL, migrating: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let imported = try await io.importJSON(from: url, allowV1Migration: migrating)
                #if os(macOS)
                let value = imported.document
                newDocument(value)
                if !imported.notes.isEmpty { notice = imported.notes.joined(separator: "\n") }
                #else
                importedDocument = imported.document
                importNotes = imported.notes
                editingImport = true
                #endif
            } catch ProjectPackageError.explicitMigrationRequired { migratingURL = url }
            catch { store.presentedError = error.localizedDescription }
        }
    }
    private func importWeather(_ url: URL) {
        guard !busy, let id = weatherScenarioID, let revision = weatherRevision else { return }
        let original = document
        busy = true
        Task {
            defer { busy = false; weatherScenarioID = nil; weatherRevision = nil }
            do {
                let imported = try await io.importWeather(from: url, into: original, scenarioID: id)
                guard store.revision == revision, document.project == original.project,
                      document.metadata == original.metadata,
                      document.preservedEntries == original.preservedEntries else {
                    throw DocumentWorkflowError.staleImport
                }
                // Attachments are append-only for the undo lifetime: undo restores
                // the previous reference while redo can still use the imported file.
                document = imported
                do { try store.replaceProject(imported.project, actionName: "导入天气文件") }
                catch { document = original; throw error }
            } catch { store.presentedError = error.localizedDescription }
        }
    }
}
#if os(iOS)
/// Imported JSON is a separate, unsaved editing session. It can be repaired before
/// exporting a new package without replacing the open DocumentGroup document.
private struct ImportedProjectEditorView: View {
    @State private var document: SimuNowDocument
    let notes: [String]
    let localAnalysisClient: any LocalAnalysisSubmitting
    let onExport: @MainActor (SimuNowDocument) -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    init(initialDocument: SimuNowDocument, notes: [String], localAnalysisClient: any LocalAnalysisSubmitting, onExport: @escaping @MainActor (SimuNowDocument) -> Void) {
        _document = State(initialValue: initialDocument); self.notes = notes; self.localAnalysisClient = localAnalysisClient; self.onExport = onExport
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("放弃导入", role: .destructive) { confirmDiscard = true }
                Spacer()
                Button("导出新项目包") { onExport(document) }.disabled(document.requiresRepair)
            }.padding()
            Text("导入副本尚未保存；修复后请导出新项目包。当前打开的项目保持独立。")
                .font(.caption).padding(.horizontal)
            ForEach(notes, id: \.self) { Text($0).font(.caption).padding(.horizontal) }
            // Type erasure keeps nested import sessions from recursively expanding
            // the concrete SwiftUI body type.
            AnyView(WorkspaceDocumentView(document: $document, localAnalysisClient: localAnalysisClient))
        }
        .interactiveDismissDisabled()
        .confirmationDialog("放弃尚未导出的导入项目？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃导入", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
    }
}
#endif
private enum DocumentWorkflowError: Error, LocalizedError {
    case staleImport
    var errorDescription: String? { "文件读取期间项目已改变，请在当前方案重新导入。" }
}
