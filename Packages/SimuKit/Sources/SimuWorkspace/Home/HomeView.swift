import SwiftUI
import UniformTypeIdentifiers
import SimuCore
import SimuDesignSystem

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
                Section {
                    RoomPageIntro("先从一个房间开始", detail: "摆好空调和座位，再比较不同设置的用电。")
                    Button { showWizard = true } label: { Label("按我的房间创建", systemImage: "plus.rectangle") }
                        .buttonStyle(.borderedProminent)
                        .padding(.vertical, 6)
                }
                Section("也可以从现成布局开始") {
                    templateButton("办公室", detail: "4 个工位 · 5 × 4 米", classroom: false) {
                        store.openProject(ProjectTemplates.office())
                    }
                    templateButton("教室", detail: "12 个座位 · 8 × 6 米", classroom: true) {
                        store.openProject(ProjectTemplates.classroom())
                    }
                    Text("模板数值需要核实；天气和温湿度请另行补充。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("继续已有项目") {
                    Button { showOpenPanel = true } label: { Label("打开已保存的房间…", systemImage: "folder") }
                    DisclosureGroup("导入旧版草稿") {
                        Button { showDraftImport = true } label: { Label("选择草稿文件…", systemImage: "arrow.up.doc") }
                        Text("支持 v1 JSON 草稿。导入后仍需补充房间信息。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !ProjectSession.recents.isEmpty {
                    Section("最近项目") {
                        ForEach(ProjectSession.recents, id: \.path) { recent in
                            Button {
                                openRecent(recent)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(recent.name)
                                    Text(URL(fileURLWithPath: recent.path).lastPathComponent)
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .help(recent.path)
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
        .modifier(RoomTheme())
    }

    private func templateButton(_ title: String, detail: String, classroom: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoomPlanMark(classroom: classroom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(.headline, design: .rounded))
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("从\(title)模板创建，\(detail)")
    }

    private func openRecent(_ recent: RecentProject) {
        do {
            try store.openPackage(at: URL(fileURLWithPath: recent.path))
        } catch {
            errorMessage = "无法打开这个房间。请通过「打开已保存的房间」重新选择文件。\n\(error.localizedDescription)"
        }
    }

    private func handle(_ result: Result<URL, Error>, _ action: (URL) throws -> Void) {
        do {
            try action(result.get())
        } catch ProjectPackageError.unsupportedVersion(let version) {
            errorMessage = "无法读取版本 \(version)。旧版草稿请使用「导入旧版草稿」；新版项目请更新 App。"
        } catch {
            errorMessage = "无法打开：\(error.localizedDescription)"
        }
    }
}
