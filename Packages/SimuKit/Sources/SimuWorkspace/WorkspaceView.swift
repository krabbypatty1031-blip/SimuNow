import SwiftUI
import SimuCore
import SimuDesignSystem
import SimuVisualization

@MainActor
public struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    private let packageIssues: [ValidationIssue]
    private let onImportJSON: (@MainActor () -> Void)?
    private let onImportWeather: (@MainActor (UUID) -> Void)?
    @State private var sheet: WorkspaceSheet?
    @State private var replacement: WorkspaceSheet?
    @State private var focusEntityID: UUID?

    public init(store: WorkspaceStore, packageIssues: [ValidationIssue] = [],
                onImportJSON: (@MainActor () -> Void)? = nil,
                onImportWeather: (@MainActor (UUID) -> Void)? = nil) {
        _store = State(initialValue: store)
        self.packageIssues = packageIssues
        self.onImportJSON = onImportJSON; self.onImportWeather = onImportWeather
    }
    public var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(WorkspaceDestination.allCases, selection: $store.selection) { destination in
                Label(destination.title, systemImage: destination.symbol).tag(destination)
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) { projectHeader; Divider(); detail }
                .navigationTitle(store.project?.name ?? "SimuNow")
                .toolbar { workspaceToolbar }
        }
        #if os(macOS)
        .inspector(isPresented: .constant(true)) {
            inspector.inspectorColumnWidth(min: 240, ideal: 290, max: 360)
        }
        #endif
        .sheet(item: $sheet) { destination in sheetContent(destination) }
        .confirmationDialog("替换当前项目的房间与所有方案？", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }), titleVisibility: .visible) {
            Button("继续创建") { sheet = replacement; replacement = nil }
            Button("取消", role: .cancel) { replacement = nil }
        } message: {
            Text("创建完成后会替换当前输入，保留项目包的已有附件。可以撤销此次替换；已有计算结果不代表新输入的结果。")
        }
        .alert("操作未完成", isPresented: Binding(get: { store.presentedError != nil },
            set: { if !$0 { store.presentedError = nil } })) {
            Button("好", role: .cancel) { store.presentedError = nil }
        } message: { Text(store.presentedError ?? "") }
    }
    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = store.project, !project.scenarios.isEmpty {
                Picker("当前方案", selection: Binding(get: { store.selectedScenarioID }, set: { store.selectedScenarioID = $0 })) {
                    ForEach(project.scenarios, id: \.id) { scenario in
                        Text(scenario.name + (scenario.id == store.baselineScenarioID ? " · 基准" : "")).tag(Optional(scenario.id))
                    }
                }.pickerStyle(.menu)
            }
            Label(saveBlocked ? "项目需要修复，修复前不能保存" : "草稿可保存", systemImage: saveBlocked ? "exclamationmark.triangle" : "doc.badge.checkmark")
                .foregroundStyle(saveBlocked ? Color.orange : Color.secondary)
            HStack {
                Text("计算输入待补充：\(preparationIssues.count) 项").font(.caption).foregroundStyle(.secondary)
                Button("查看问题") { sheet = .issues }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var detail: some View {
        switch store.selection ?? .workspace {
        case .workspace:
            if let project = store.project, let id = store.selectedScenarioID, !project.geometry.rooms.isEmpty {
                RoomObjectsView(project: project, scenarioID: id, registry: store.modelRegistry,
                                focusEntityID: focusEntityID, onCommit: commit)
                    .id("\(id)-\(focusEntityID?.uuidString ?? "")")
            } else {
                EmptyStateView("建立房间模型", symbol: "square.dashed", message: "通过矩形房间向导或办公室、教室模板开始；未知输入可保留为草稿。")
            }
        case .scenarios:
            if let project = store.project {
                ScenarioListView(project: project, selectedScenarioID: store.selectedScenarioID,
                    baselineScenarioID: store.baselineScenarioID, onSelect: { store.selectedScenarioID = $0 },
                    onCommit: commit, onSetBaseline: { try store.setBaseline($0) })
            }
        case .runs:
            EmptyStateView("计算引擎尚未接入", symbol: "waveform.path", message: "当前可以编辑和保存模型、检查输入、捕获方案快照。快照不是计算结果。")
        case .reports:
            EmptyStateView("暂无有效报告", symbol: "doc.text", message: "后续接入计算和质量检查后才可生成报告；当前模型不能给出能耗、舒适或节省结论。")
        }
    }
    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("矩形房间向导") { requestCreation(.wizard) }
                Button("办公室 / 教室模板") { requestCreation(.templates) }
                if let onImportJSON { Button("导入 JSON 为新项目", action: onImportJSON) }
            } label: { Label("创建与导入", systemImage: "plus") }
            Menu {
                if let project = store.project {
                    ForEach(project.geometry.rooms, id: \.id) { room in
                        Button("房间：\(room.name)") { sheet = .room(room.id) }
                    }
                    if let id = store.selectedScenarioID { Button("当前方案使用条件") { sheet = .conditions(id) } }
                    Button("项目名称") { sheet = .identity }
                    Button("未知与假设摘要") { sheet = .assumptions }
                    Button("捕获当前方案输入快照") {
                        do { _ = try store.captureSelectedInput(); sheet = .snapshot }
                        catch { store.presentedError = error.localizedDescription }
                    }.disabled(store.selectedScenarioID == nil || saveBlocked)
                }
            } label: { Label("编辑与检查", systemImage: "slider.horizontal.3") }
            Button { store.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                .disabled(!store.canUndo).help(store.undoActionName.map { "撤销\($0)" } ?? "撤销")
                .keyboardShortcut("z", modifiers: .command)
            Button { store.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }
                .disabled(!store.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
    private var inspector: some View {
        Form {
            Section("项目") {
                LabeledContent("房间", value: "\(store.project?.geometry.rooms.count ?? 0)")
                LabeledContent("方案", value: "\(store.project?.scenarios.count ?? 0)")
                Text("房间、门窗、家具由所有方案共享；人员、空调与使用条件属于当前方案。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("输入状态") {
                Text(saveBlocked ? "需要修复" : "草稿完整性通过")
                Text(preparationIssues.isEmpty ? "输入准备检查通过；计算引擎尚未接入。" : "当前方案仍有 \(preparationIssues.count) 项计算输入待补充。")
                Button("定位输入问题") { sheet = .issues }
                Button("查看未知与假设") { sheet = .assumptions }
            }
        }.formStyle(.grouped)
    }
    @ViewBuilder private func sheetContent(_ destination: WorkspaceSheet) -> some View {
        switch destination {
        case .wizard:
            NavigationStack { RoomWizardView(registry: store.modelRegistry) { try store.createRoomProject($0) } }.modifier(EditorSheetSize())
        case .templates:
            TemplatePickerView { try store.applyTemplate($0, templateID: $1, templateVersion: $2) }
        case .room(let id):
            if let project = store.project {
                NavigationStack { RoomEditorView(project: project, roomID: id, registry: store.modelRegistry, onCommit: commit) }.modifier(EditorSheetSize())
            }
        case .opening(let roomID, let openingID):
            if let project = store.project {
                NavigationStack { OpeningEditorView(project: project, roomID: roomID, openingID: openingID, registry: store.modelRegistry, onCommit: commit) }.modifier(EditorSheetSize())
            }
        case .conditions(let id):
            if let project = store.project, let draft = try? ScenarioConditionsDraft(project: project, scenarioID: id) {
                ScenarioConditionsView(project: project, draft: draft, onCommit: commit,
                    onImportWeather: { onImportWeather?(id) }, onClearWeather: {
                        guard var candidate = store.project, let index = candidate.scenarios.firstIndex(where: { $0.id == id }) else { return }
                        candidate.scenarios[index].inputs.environment.weather = nil
                        try commit(candidate, "移除天气引用")
                    })
            }
        case .assumptions:
            sheetFrame("未知与假设") { if let project = store.project { ParameterAssumptionsView(project: project, registry: store.modelRegistry) } }
        case .issues:
            sheetFrame("输入问题") {
                if allIssues.isEmpty { Text("当前检查没有发现输入问题。计算引擎尚未接入。") }
                ForEach(Array(allIssues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(issue.blocks.contains(.projectIntegrity) ? "保存前修复" : "计算前补充", systemImage: "exclamationmark.circle")
                        Text(ValidationPresentation.describe(issue))
                        if canLocate(issue) { Button("前往编辑") { locate(issue) } }
                        DisclosureGroup("字段路径") { Text(issue.path).font(.caption).textSelection(.enabled) }
                    }.padding(.vertical, 4)
                }
            }
        case .snapshot:
            sheetFrame("独立输入快照") {
                if let snapshot = store.capturedInput {
                    Text("已捕获当前方案。后续编辑不会改写该快照；几何也在快照内。")
                    LabeledContent("方案 ID", value: snapshot.scenarioID.uuidString)
                    LabeledContent("房间数", value: "\(snapshot.geometry.rooms.count)")
                    Text("允许含未知的草稿快照，不是可求解 RunInput，也不含计算结果。").foregroundStyle(.secondary)
                }
            }
        case .identity:
            if let project = store.project { ProjectNameView(name: project.name) { name in
                guard var candidate = store.project else { return }
                candidate.name = name; try commit(candidate, "修改项目名称")
            } }
        }
    }
    private func sheetFrame<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            Form { content() }.formStyle(.grouped).navigationTitle(title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
        }.modifier(EditorSheetSize())
    }
    private var saveBlocked: Bool { allIssues.contains { $0.blocks.contains(.projectIntegrity) } }
    private var preparationIssues: [ValidationIssue] { allIssues.filter { $0.blocks.contains(.inputPreparation) } }
    private var allIssues: [ValidationIssue] {
        let integrity = store.integrityReport.issues.filter { $0.blocks.contains(.projectIntegrity) }
        let scopedPackage = packageIssues.filter { issue in
            issue.blocks.contains(.projectIntegrity) || issue.entityID == store.selectedScenarioID || !issue.path.hasPrefix("/scenarios/")
        }
        var seen: Set<String> = []
        return (integrity + store.selectedScenarioReport.issues + scopedPackage).filter {
            seen.insert("\($0.code)|\($0.path)|\($0.entityID?.uuidString ?? "")").inserted
        }
    }
    private func commit(_ project: ProjectDocument, _ actionName: String) throws { try store.replaceProject(project, actionName: actionName) }
    private func requestCreation(_ destination: WorkspaceSheet) {
        if store.project?.geometry.rooms.isEmpty == false { replacement = destination } else { sheet = destination }
    }
    private func canLocate(_ issue: ValidationIssue) -> Bool {
        issue.code == "baseline_reference" || issue.path.hasPrefix("/geometry/") || issue.path.hasPrefix("/scenarios/")
    }
    private func locate(_ issue: ValidationIssue) {
        guard let project = store.project else { return }
        if issue.code == "baseline_reference" { sheet = nil; store.selection = .scenarios; return }
        let parts = issue.path.split(separator: "/").map(String.init)
        if parts.first == "geometry", parts.count > 2, parts[1] == "rooms", let index = Int(parts[2]), project.geometry.rooms.indices.contains(index) {
            let room = project.geometry.rooms[index]
            if let id = issue.entityID, room.openings.contains(where: { $0.id == id }) { sheet = .opening(room.id, id) }
            else { sheet = .room(room.id) }; return
        }
        if parts.first == "scenarios", parts.count > 1, let index = Int(parts[1]), project.scenarios.indices.contains(index) {
            store.selectedScenarioID = project.scenarios[index].id
            if parts.contains("envelope") || parts.contains("ventilation") || parts.contains("environment") || parts.contains("cost") {
                sheet = .conditions(project.scenarios[index].id); return
            }
        }
        sheet = nil; store.selection = .workspace; focusEntityID = issue.entityID
    }
}
private enum WorkspaceSheet: Hashable, Identifiable {
    case wizard, templates, room(UUID), opening(UUID, UUID), conditions(UUID), assumptions, issues, snapshot, identity
    var id: Self { self }
}
private struct EditorSheetSize: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.frame(minWidth: 560, idealWidth: 680, minHeight: 500, idealHeight: 720)
        #else
        content
        #endif
    }
}
private struct ProjectNameView: View {
    @State var name: String
    let onApply: @MainActor (String) throws -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("项目名称", text: $name)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("项目名称").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("应用") {
                    do {
                        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { throw RoomEditingError.nameRequired }
                        try onApply(value); dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }
        }.modifier(EditorSheetSize())
    }
}
