import SwiftUI
import UniformTypeIdentifiers
import SimuCore
import SimuDesignSystem
import SimuVisualization

public struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    @State private var isOpeningPackage = false
    @State private var isSavingPackage = false

    public init(store: WorkspaceStore) {
        self._store = State(initialValue: store)
    }

    public var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(WorkspaceDestination.allCases, selection: $store.selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
                .navigationTitle(store.selection?.title ?? "SimuNow")
                // Attach to the detail column so macOS actually shows items in the title bar.
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("打开") {
                            openPackage()
                        }
                        .accessibilityLabel("打开项目包")
                        Button("保存") {
                            savePackage()
                        }
                        .disabled(store.project == nil)
                        .accessibilityLabel("保存项目包")
                        Menu("模板") {
                            Button("办公室") {
                                store.loadOfficeTemplate()
                            }
                            .accessibilityLabel("从办公室模板创建项目")
                            Button("教室") {
                                store.loadClassroomTemplate()
                            }
                            .accessibilityLabel("从教室模板创建项目")
                        }
                        .accessibilityLabel("从模板创建项目")
                    }
                }
        }
        .fileImporter(
            isPresented: $isOpeningPackage,
            allowedContentTypes: [.folder, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImportedURL(result)
        }
        .fileImporter(
            isPresented: $isSavingPackage,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleSaveFolder(result)
        }
        #if os(macOS)
        .inspector(isPresented: .constant(true)) {
            RoomEditorForm(store: store)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection ?? .workspace {
        case .workspace:
            workspaceDetail
        case .scenarios:
            if let baseline = store.baseline, let current = store.project {
                Form {
                    Section("基准方案") {
                        LabeledContent("方案 ID", value: store.baselineScenarioID?.uuidString ?? "无")
                        LabeledContent("基准长度 m", value: String(baseline.geometry?.sizeX.value ?? 0))
                        Text("基准是输入快照，不含计算结果。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("当前编辑") {
                        LabeledContent("当前长度 m", value: String(current.geometry?.sizeX.value ?? 0))
                        Text("改当前房间不会覆盖基准 JSON。")
                            .font(.footnote)
                    }
                }
                .formStyle(.grouped)
            } else {
                EmptyStateView("暂无方案", symbol: "square.stack.3d.up", message: "从办公室或教室模板创建后，这里显示冻结基准与当前编辑。")
            }
        case .runs:
            EmptyStateView("暂无计算任务", symbol: "waveform.path", message: "计算引擎接入后，这里显示任务进度与质量状态。")
        case .reports:
            EmptyStateView("暂无报告", symbol: "doc.text", message: "通过质量检查的结果可用于生成建议报告。")
        }
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        let incomplete = store.project?.hasCompletePhysicalModel != true
        #if os(macOS)
        if store.project == nil {
            emptyProjectPane
        } else {
            SimulationViewport(showsIncompleteModel: incomplete)
        }
        #else
        NavigationStack {
            VStack(spacing: 0) {
                if store.project == nil {
                    emptyProjectPane
                } else {
                    SimulationViewport(showsIncompleteModel: incomplete)
                }
                NavigationLink("编辑房间参数") {
                    RoomEditorForm(store: store)
                }
                .padding()
                .accessibilityLabel("编辑房间参数")
            }
        }
        #endif
    }

    /// Visible start actions; the title-bar 模板 menu is easy to miss on macOS split views.
    private var emptyProjectPane: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                "房间工作区",
                symbol: "cube.transparent",
                message: "还没有项目。从办公室或教室模板开始，或打开已有的 .simunow 包。计算引擎尚未接入。"
            )
            HStack(spacing: 12) {
                Button("办公室模板") {
                    store.loadOfficeTemplate()
                }
                .accessibilityLabel("从办公室模板创建项目")
                Button("教室模板") {
                    store.loadClassroomTemplate()
                }
                .accessibilityLabel("从教室模板创建项目")
                Button("打开项目包") {
                    openPackage()
                }
                .accessibilityLabel("打开项目包")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPackage() {
        #if os(macOS)
        if let url = ProjectLocationPicker.requestOpenURL() {
            store.openPackage(at: url)
        }
        #else
        isOpeningPackage = true
        #endif
    }

    private func savePackage() {
        if store.packageURL != nil {
            store.savePackage()
            return
        }
        #if os(macOS)
        if let url = ProjectLocationPicker.requestSaveURL() {
            store.savePackage(to: url)
        }
        #else
        isSavingPackage = true
        #endif
    }

    private func handleImportedURL(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            store.openPackage(at: url)
        case .failure(let error):
            store.packageError = error.localizedDescription
        }
    }

    private func handleSaveFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folder = urls.first else { return }
            let name = store.project?.name ?? "Project"
            let url = folder.appendingPathComponent("\(name).\(ProjectPackage.packageExtension)", isDirectory: true)
            store.savePackage(to: url)
        case .failure(let error):
            store.packageError = error.localizedDescription
        }
    }
}
