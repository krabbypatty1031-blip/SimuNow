import SwiftUI
import UniformTypeIdentifiers
import SimuCore

/// Entry screen: create from wizard/templates, open packages, migrate v1 drafts, recent list.
public struct HomeView: View {
    let store: WorkspaceStore
    @State private var showWizard = false
    @State private var showOpenPanel = false
    @State private var showDraftImport = false
    @State private var errorMessage: String?

    public init(store: WorkspaceStore) { self.store = store }

    public var body: some View {
        NavigationStack {
            List {
                Section("新建") {
                    Button { showWizard = true } label: { Label("创建房间…", systemImage: "plus.rectangle") }
                    Button { store.openProject(ProjectTemplates.office()) } label: { Label("办公室模板", systemImage: "briefcase") }
                    Button { store.openProject(ProjectTemplates.classroom()) } label: { Label("教室模板", systemImage: "graduationcap") }
                    Text("模板包含预设与假设参数；环境与天气保持未知，可在假设列表查看。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("打开") {
                    Button { showOpenPanel = true } label: { Label("打开项目包 (.simunow)…", systemImage: "folder") }
                    Button { showDraftImport = true } label: { Label("导入 v1 草稿…", systemImage: "arrow.up.doc") }
                }
                if !ProjectSession.recents.isEmpty {
                    Section("最近项目") {
                        ForEach(ProjectSession.recents, id: \.path) { recent in
                            Button {
                                openRecent(recent)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(recent.name)
                                    Text(recent.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SimuNow")
            .sheet(isPresented: $showWizard) {
                RoomWizardView { project in store.openProject(project) }
            }
            .fileImporter(isPresented: $showOpenPanel, allowedContentTypes: [.folder]) { result in
                handle(result) { url in
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    try store.openPackage(at: url)
                }
            }
            .fileImporter(isPresented: $showDraftImport, allowedContentTypes: [.json]) { result in
                handle(result) { url in
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let migrated = try ProjectMigrator.migrate(Data(contentsOf: url))
                    store.openProject(migrated.project)
                    errorMessage = migrated.notes.joined(separator: "\n")
                }
            }
            .alert("提示", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func openRecent(_ recent: RecentProject) {
        do {
            try store.openPackage(at: URL(fileURLWithPath: recent.path))
        } catch {
            errorMessage = "无法打开：\(error.localizedDescription)\n（沙盒环境下可能需要重新通过「打开项目包」选择文件。）"
        }
    }

    private func handle(_ result: Result<URL, Error>, _ action: (URL) throws -> Void) {
        do {
            try action(result.get())
        } catch ProjectPackageError.unsupportedVersion(let version) {
            errorMessage = "项目版本 \(version) 不受支持：v1 请使用「导入 v1 草稿」，更高版本需要更新 App。"
        } catch {
            errorMessage = "无法打开：\(error.localizedDescription)"
        }
    }
}
