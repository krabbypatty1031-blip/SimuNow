import SwiftUI
import SimuCore
import SimuDesignSystem
import SimuVisualization
import SimuSimulation

@MainActor
public struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    private let nativeEntries: [String:ProjectPackageEntry]
    private let rendererCapability: RendererCapabilities
    private let nativeSidefileRevision: UUID
    private let weatherReturnScenarioID: UUID?
    private let weatherReturnRevision: UUID
    private let packageIssues: [ValidationIssue]
    private let onImportJSON: (@MainActor () -> Void)?
    private let onImportWeather: (@MainActor (UUID) -> Void)?
    @State private var sheet: WorkspaceSheet?
    @State private var replacement: WorkspaceSheet?
    @State private var focusEntityID: UUID?
    @State private var focusField: String?
    @State private var focusOrdinal: Int?
    @State private var selectedSceneKey: SceneObjectKey?
    #if os(macOS)
    @State private var inspectorPresented = true
    #else
    @State private var inspectorPresented = false
    #endif
    @State private var showingPreview = false
    @State private var showingEstimates = false
    @State private var pendingWeatherImportID: UUID?
    @State private var relatedSheet: WorkspaceSheet?

    public init(store: WorkspaceStore, nativeEntries: [String:ProjectPackageEntry] = [:], nativeSidefileRevision: UUID = UUID(), rendererCapability: RendererCapabilities = .current, weatherReturnScenarioID: UUID? = nil, weatherReturnRevision: UUID = UUID(), packageIssues: [ValidationIssue] = [],
                onImportJSON: (@MainActor () -> Void)? = nil,
                onImportWeather: (@MainActor (UUID) -> Void)? = nil) {
        _store = State(initialValue: store)
        self.rendererCapability = rendererCapability; self.nativeEntries = nativeEntries; self.nativeSidefileRevision = nativeSidefileRevision
        self.weatherReturnScenarioID = weatherReturnScenarioID; self.weatherReturnRevision = weatherReturnRevision
        self.packageIssues = packageIssues
        self.onImportJSON = onImportJSON; self.onImportWeather = onImportWeather
    }
    public var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("工作流程") {
                    ForEach(WorkspaceDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.symbol).tag(destination)
                    }
                }
                if let project = store.project {
                    Section("方案 · 当前编辑") {
                        ForEach(project.scenarios, id: \.id) { scenario in
                            Button { store.selectedScenarioID = scenario.id } label: {
                                Label(scenario.name, systemImage: scenario.id == store.selectedScenarioID ? "checkmark.circle.fill" : scenario.id == store.baselineScenarioID ? "flag" : "circle")
                                    .fixedSize(horizontal: false, vertical: true)
                            }.buttonStyle(.plain).help(scenario.name)
                        }
                    }
                    Section("项目输入") {
                        ForEach(project.geometry.rooms, id: \.id) { room in
                            Button(room.name, systemImage: "square.dashed") { sheet = .room(room.id) }
                        }
                        Button("使用条件", systemImage: "sun.max") { if let id = store.selectedScenarioID { sheet = .conditions(id) } }
                        Button("输入问题", systemImage: "exclamationmark.circle") { sheet = .issues }
                        Button("未知与假设", systemImage: "questionmark.circle") { sheet = .assumptions }
                    }
                }
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) { projectHeader; Divider(); detail }
                .navigationTitle(store.project?.name ?? "SimuNow")
                .toolbar { workspaceToolbar }
        }
         .sheet(item: $sheet, onDismiss: {
            if let id = pendingWeatherImportID { pendingWeatherImportID = nil; onImportWeather?(id) }
            focusField = nil; focusEntityID = nil; focusOrdinal = nil
        }) { destination in sheetContent(destination).environment(\.editorFocus, EditorFocus(entityID: focusEntityID, field: focusField, ordinal: focusOrdinal)) }
        .confirmationDialog("替换当前项目的房间与所有方案？", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }), titleVisibility: .visible) {
            Button("继续创建") { sheet = replacement; replacement = nil }
            Button("取消", role: .cancel) { replacement = nil }
        } message: {
            Text("创建完成后会替换当前输入，保留项目包的已有附件。可以撤销此次替换；已有计算结果不代表新输入的结果。")
        }
        .onChange(of: weatherReturnRevision) { _, _ in
            if let id = weatherReturnScenarioID, store.project?.scenarios.contains(where: { $0.id == id }) == true {
                store.selectedScenarioID = id; focusEntityID = id; focusField = "代表日"; focusOrdinal = nil
                sheet = .conditions(id)
            }
        }
        .onChange(of: store.selection) { _, _ in
            if sheet == .dailySettings { sheet = nil }
        }
        .onAppear { if store.preview.enabled { store.preview.update(previewInput,registry:store.modelRegistry,persist:persistPreview) } }
        .onChange(of: previewInput) { _, input in
            store.preview.update(input,registry: store.modelRegistry,persist: persistPreview)
        }
        .onChange(of: estimateInput) { _, input in store.estimates.update(input,registry:store.modelRegistry) }
        .onAppear { store.estimates.update(estimateInput,registry:store.modelRegistry) }
        .onDisappear { store.preview.stop();store.estimates.stop() }
        .alert("操作未完成", isPresented: Binding(get: { store.presentedError != nil },
            set: { if !$0 { store.presentedError = nil } })) {
            Button("好", role: .cancel) { store.presentedError = nil }
        } message: { Text(store.presentedError ?? "") }
    }
    private var projectHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { headerContent }
            VStack(alignment: .leading, spacing: 6) { headerContent }
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }
    @ViewBuilder private var headerContent: some View {
        if let project = store.project, !project.scenarios.isEmpty {
            Picker("编辑方案", selection: Binding(get: { store.selectedScenarioID }, set: { store.selectedScenarioID = $0 })) {
                ForEach(project.scenarios, id: \.id) { scenario in
                    Text(scenario.name + (scenario.id == store.baselineScenarioID ? " · 基准" : "")).tag(Optional(scenario.id))
                }
            }.pickerStyle(.menu)
        }
        Spacer(minLength: 0)
        Button { sheet = .issues } label: {
            Label(saveBlocked ? "保存前需修复" : "输入允许保存", systemImage: saveBlocked ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
        }.buttonStyle(.plain).help("保存资格不表示已写入磁盘。使用系统文件菜单保存项目（⌘S）。")
    }
    @ViewBuilder private var detail: some View {
        switch store.selection ?? .workspace {
        case .workspace:
            if let project = store.project, let id = store.selectedScenarioID, !project.geometry.rooms.isEmpty {
                RoomObjectsView(project: project, scenarioID: id, registry: store.modelRegistry,
                    focusEntityID: focusEntityID, overlay: store.preview.overlay, rendererCapability: rendererCapability,
                    selectedSceneKey: selectedSceneKey, inspectorPresented: $inspectorPresented,
                    onSelectionChange: { selectedSceneKey = $0 }, focusField: focusField, onCommit: commit)
                    .safeAreaInset(edge: .bottom) {
                        ViewThatFits(in: .horizontal) {
                            HStack { analysisControls }
                            VStack(alignment: .leading) { analysisControls }
                        }.padding(10).background(.regularMaterial)
                    }
            } else {
                VStack(spacing: 16) {
                    EmptyStateView("建立你的房间", symbol: "square.dashed", message: "创建房间，设置空调方向，再观察假设路径和家具遮挡。未知物理输入可以保留。")
                    Button("从家庭 / 办公室 / 教室模板开始") { requestCreation(.templates) }.buttonStyle(.borderedProminent)
                    Button("手动输入房间尺寸") { requestCreation(.wizard) }
                }.padding()
            }
        case .scenarios:
            if let project = store.project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PreviewComparisonView(store: store, additionalIssues: packageIssues)
                        FixedPreviewComparisonView(store: store, entries: nativeEntries, revision: nativeSidefileRevision)
                        EstimateComparisonView(store:store,entries:nativeEntries,revision:nativeSidefileRevision,additionalIssues:packageIssues)
                        DisclosureGroup("管理方案 · 复制、名称与基准") {
                            ScenarioListView(project: project, selectedScenarioID: store.selectedScenarioID,
                                baselineScenarioID: store.baselineScenarioID, onSelect: { store.selectedScenarioID = $0 },
                                onCommit: commit, onSetBaseline: { try store.setBaseline($0) },
                                onCopy: { edited, sourceID in
                                    guard store.project == project else { throw PreviewConfigurationEditingError.staleDraft }
                                    try store.replaceProject(edited, actionName: "复制方案", copiedFromScenarioID: sourceID)
                                })
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .runs:
            NativeAnalysisHistoryView(store:store,entries:nativeEntries,revision:nativeSidefileRevision)
        case .reports:
            LocalReportView(store: store, entries: nativeEntries, revision: nativeSidefileRevision)
        case .measurements:
            MeasurementWorkspaceView(store: store, entries: nativeEntries, revision: nativeSidefileRevision)
        }
    }
    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("矩形房间向导") { requestCreation(.wizard) }
                Button("家庭 / 办公室 / 教室模板") { requestCreation(.templates) }
                #if os(iOS)
                Button("RoomPlan 扫描 / 手动回退") { requestCreation(.capture) }
                #endif
                if let onImportJSON { Button("导入 JSON 为新项目", action: onImportJSON) }
            } label: { Label("创建与导入", systemImage: "plus") }
            if store.selection == .workspace {
                Button("日常设置", systemImage: "slider.horizontal.3") { sheet = .dailySettings }
                    .disabled(store.currentScenario == nil)
                Button("属性", systemImage: "sidebar.right") { inspectorPresented.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
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
            } label: { Label("项目与证据", systemImage: "slider.horizontal.3") }
            Button { store.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                .disabled(!store.canUndo).help(store.undoActionName.map { "撤销\($0)" } ?? "撤销")
                .keyboardShortcut("z", modifiers: .command)
            Button { store.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }
                .disabled(!store.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
    @ViewBuilder private func sheetContent(_ destination: WorkspaceSheet) -> some View {
        switch destination {
        case .dailySettings:
            if let id = store.selectedScenarioID {
                sheetFrame("日常设置") {
                    DailySettingsView(store: store, onRoom: { sheet = .room($0) },
                        onAdvanced: { sheet = .conditions(id) }, onObject: { objectID in
                            selectedSceneKey = sceneKey(for: objectID)
                            inspectorPresented = true
                            focusEntityID = objectID
                            sheet = .object(objectID)
                        })
                }
            }
        case .capture:
            let instance = store.documentInstanceID, inputRevision = store.revision
            RoomCaptureWorkflowView(onManual: { sheet = .wizard }) { snapshot, original in
                let worker = Task.detached { try RoomCaptureArtifact.make(snapshot, original: original) }
                let artifact = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                try store.validateNativeDocumentContext(instanceID: instance)
                guard store.revision == inputRevision else { throw PreviewConfigurationEditingError.staleDraft }
                try store.applyRoomCapture(artifact)
            }
        case .direction:
            if let project = store.project, let scenario = store.currentScenario {
                DailyDirectionEditor(project: project, scenario: scenario) { candidate in
                    guard store.project == project, store.selectedScenarioID == scenario.id else { throw PreviewConfigurationEditingError.staleDraft }
                    try store.replaceProject(candidate, actionName: "调整送风方向")
                }
            }
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
                    onImportWeather: onImportWeather == nil ? nil : { pendingWeatherImportID = id; relatedSheet = nil; sheet = nil }, onClearWeather: {
                        guard var candidate = store.project, let index = candidate.scenarios.firstIndex(where: { $0.id == id }) else { return }
                        candidate.scenarios[index].inputs.environment.weather = nil
                        try commit(candidate, "移除天气引用")
                    })
            }
        case .assumptions:
            sheetFrame("未知与假设") { if let project = store.project { ParameterAssumptionsView(project: project, registry: store.modelRegistry, scenarioID: store.selectedScenarioID, onLocate: { path in locatePath(path, returnTo: .assumptions) }) } }
        case .issues:
            sheetFrame("输入问题") {
                if allIssues.isEmpty { Text("当前检查没有发现问题。本地规则与简化估算按各自输入条件运行。") }
                capabilitySummary
                DisclosureGroup("保存完整性与高级物理输入 · \(allIssues.count) 项") {
                ForEach(Array(allIssues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(issue.blocks.contains(.projectIntegrity) ? "保存前修复" : "高级物理输入补充", systemImage: "exclamationmark.circle")
                        Text(store.project.map { FieldNavigation.objectName(project: $0, path: issue.path, entityID: issue.entityID) } ?? "项目")
                        Text(ValidationPresentation.message(for: issue))
                        if canLocate(issue) { Button(FieldNavigation.field(issue.path) == nil ? "查看相关输入" : "定位字段并编辑") { locate(issue) } }
                        else { Text("此问题暂不能自动定位；请保留原数据并检查项目格式。").font(.caption) }
                        DisclosureGroup("字段路径") { Text(issue.path).font(.caption).textSelection(.enabled) }
                    }.padding(.vertical, 4)
                }
                }
            }
        case .object(let id):
            if let project = store.project, let scenarioID = store.selectedScenarioID,
               let selection = objectParent(id, project: project, scenarioID: scenarioID) {
                RoomObjectEditorView(project: project, scenarioID: scenarioID, selection: selection, registry: store.modelRegistry, onCommit: commit)
            } else {
                sheetFrame("无法自动定位对象") { Text("对象已变化或关联失效。请在对象清单中使用对应的关联修复入口；原数据保留。") }
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
            EditorForm { content() }.navigationTitle(title)
                .sheet(item: $relatedSheet, onDismiss: { focusField = nil; focusEntityID = nil; focusOrdinal = nil }) { destination in
                    AnyView(sheetContent(destination)).environment(\.editorFocus, EditorFocus(entityID: focusEntityID, field: focusField, ordinal: focusOrdinal))
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
        }.modifier(EditorSheetSize())
    }
    private var estimateInput:EstimateWorkspaceInput {
        .init(project:store.project,scenarioID:store.selectedScenarioID,configuration:store.analysisConfiguration,additionalIssues:packageIssues)
    }
    private var previewInput: PreviewWorkspaceInput {
        .init(project:store.project,scenarioID:store.selectedScenarioID,configuration:store.selectedScenarioID.flatMap { store.analysisConfiguration?.configuration(scenarioID:$0,kind:.airflowPreview) }, additionalIssues:packageIssues)
    }
    private func persistPreview(_ artifact:NativeAnalysisArtifact) throws {
        guard let persist=store.persistNativeAnalysis else { throw NativeArtifactError.unsupportedRecord };try persist(artifact)
    }
    private var saveBlocked: Bool { allIssues.contains { $0.blocks.contains(.projectIntegrity) } }
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
    @ViewBuilder private var analysisControls: some View {
        MethodBoundaryView()
        if store.preview.isPending { ProgressView().controlSize(.small); Text("正在更新…").font(.caption) }
        else if store.preview.currentResult != nil { Label("当前输入已生成预览", systemImage: "checkmark.circle").font(.caption) }
        Button(store.preview.currentResult == nil ? "设置并预览" : "预览与遮挡结果", systemImage: "wind") { showingPreview.toggle() }
            .buttonStyle(.borderedProminent)
            .popover(isPresented: $showingPreview) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AirflowPreviewPanelView(store: store, input: previewInput, onLocate: { id in
                            selectedSceneKey = sceneKey(for: id); inspectorPresented = true; showingPreview = false
                        }, onRepair: { issue in showingPreview = false; locateAnalysis(issue) })
                        DisclosureGroup("条件建议与依据") {
                            SuggestionCardsView(store: store, onDirection: {
                                showingPreview = false; sheet = .direction
                            }, onObject: { id in
                                selectedSceneKey = sceneKey(for: id)
                                inspectorPresented = true; showingPreview = false
                            })
                        }
                    }.padding(18)
                }
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, minHeight: 280, idealHeight: 440, maxHeight: 540)
            }
        Button("更新预览", systemImage: "arrow.clockwise") {
            if store.preview.enabled { store.preview.retry(registry: store.modelRegistry, persist: persistPreview) }
            else { showingPreview = true }
        }.labelStyle(.iconOnly).keyboardShortcut("r", modifiers: [.command, .shift]).help("更新预览（⌘⇧R）")
        Button("电量与显热情景") { showingEstimates.toggle() }
            .popover(isPresented: $showingEstimates) {
                ScrollView { ThermalEstimatePanelView(store:store,entries:nativeEntries,input:estimateInput).padding(18) }
                    .frame(minWidth: 320, idealWidth: 440, maxWidth: 560, minHeight: 280, idealHeight: 480, maxHeight: 540)
            }
    }
    @ViewBuilder private var capabilitySummary: some View {
        if let project = store.project {
            ForEach(AnalysisCapability.allCases, id: \.rawValue) { capability in
                let config = AnalysisKind(rawValue: capability.rawValue).flatMap { kind in
                    store.selectedScenarioID.flatMap { store.analysisConfiguration?.configuration(scenarioID: $0, kind: kind) }
                }
                let readiness = AnalysisReadinessEvaluator(registry: store.modelRegistry).evaluate(project: project, scenarioID: store.selectedScenarioID, capability: capability, configuration: config, additionalIssues: packageIssues)
                VStack(alignment: .leading, spacing: 8) {
                    Label(capabilityTitle(capability) + (readiness.eligible ? " · 输入可用" : " · \(readiness.blockers.count) 项待处理"), systemImage: readiness.eligible ? "checkmark.circle" : "exclamationmark.circle")
                    ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { _, issue in
                        Text(issue.message).font(.callout)
                        if issue.fieldPath != "/analysis/configuration" {
                            Button("定位并修复") { locateAnalysis(issue) }
                        } else {
                            Button("进入工作区设置此方法") { sheet = nil; store.selection = .workspace; showingPreview = capability == .airflowPreview; showingEstimates = capability != .airflowPreview }
                        }
                    }
                }.padding(12).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    private func capabilityTitle(_ capability: AnalysisCapability) -> String {
        switch capability { case .roomView: "房间查看"; case .airflowPreview: "风向与遮挡"; case .powerEstimate: "电量情景"; case .steadyHeatBalance: "显热情景" }
    }
    private func entityID(at path: String) -> UUID? {
        guard let project = store.project else { return nil }
        let tree = try? JSONTreeCoding.encode(project)
        let parts = path.split(separator: "/").map(String.init)
        var node = tree
        var id: UUID?
        for part in parts {
            if let node { for key in ["id", "surfaceID", "openingID", "roomID", "deviceID", "seatID"] {
                if let value = node[key]?.string, let found = UUID(uuidString: value) { id = found; break }
            } }
            if let index = Int(part) { node = node?.items.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
            else { node = node?[part] }
        }
        if let node { for key in ["id", "surfaceID", "openingID", "roomID", "deviceID", "seatID"] {
            if let value = node[key]?.string, let found = UUID(uuidString: value) { id = found; break }
        } }
        return id
    }
    private func locatePath(_ path: String, returnTo: WorkspaceSheet) {
        locate(.init(code: "missing_parameter", path: path, entityID: entityID(at: path), blocks: [], message: "输入待补充"))
    }
    private func locateAnalysis(_ issue: AnalysisIssue) {
        if issue.fieldPath.hasPrefix("/analysis/") || issue.fieldPath.hasPrefix("/configuration") {
            relatedSheet = nil; sheet = nil; store.selection = .workspace
            showingPreview = issue.scope == .airflowPreview
            showingEstimates = issue.scope != .airflowPreview
            return
        }
        locate(.init(code: issue.code, path: issue.fieldPath, entityID: issue.entityID, blocks: [], message: issue.message))
    }
    private func sceneKey(for id: UUID) -> SceneObjectKey? {
        guard let project = store.project, let scenario = project.scenarios.first(where: { $0.id == store.selectedScenarioID }) else { return nil }
        if project.geometry.obstacles.contains(where: { $0.id == id }) { return .init(category: .furniture, modelID: id) }
        if scenario.inputs.usage.seats.contains(where: { $0.id == id }) { return .init(category: .seat, modelID: id) }
        if scenario.inputs.usage.seats.flatMap(\.samples).contains(where: { $0.id == id }) { return .init(category: .sample, modelID: id) }
        if scenario.inputs.hvac.flatMap(\.ports).contains(where: { $0.id == id }) { return .init(category: .port, modelID: id) }
        return nil
    }
    private func routeEditor(_ destination: WorkspaceSheet) {
        if sheet == .issues || sheet == .assumptions { relatedSheet = destination }
        else { sheet = destination }
    }
    private func objectParent(_ id: UUID, project: ProjectDocument, scenarioID: UUID) -> RoomPlanSelection? {
        if project.geometry.obstacles.contains(where: { $0.id == id }) { return .init(kind: .furniture, objectID: id) }
        guard let input = project.scenarios.first(where: { $0.id == scenarioID })?.inputs else { return nil }
        if let seat = input.usage.seats.first(where: { $0.id == id || $0.samples.contains { $0.id == id } }) { return .init(kind: .seat, objectID: seat.id) }
        if let occupant = input.usage.occupants.first(where: { $0.id == id }), input.usage.seats.contains(where: { $0.id == occupant.seatID }) { return .init(kind: .seat, objectID: occupant.seatID) }
        if let control = input.controls.first(where: { $0.id == id }), input.hvac.contains(where: { $0.id == control.deviceID }) { return .init(kind: .hvac, objectID: control.deviceID) }
        if let device = input.hvac.first(where: { $0.id == id || $0.ports.contains { $0.id == id } }) { return .init(kind: .hvac, objectID: device.id) }
        if input.usage.equipment.contains(where: { $0.id == id }) { return .init(kind: .equipment, objectID: id) }
        return nil
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
        focusEntityID = issue.entityID ?? entityID(at: issue.path)
        focusField = FieldNavigation.field(issue.path)
        focusOrdinal = FieldNavigation.ordinal(issue.path)
        if issue.code == "baseline_reference" { sheet = nil; store.selection = .scenarios; return }
        let parts = issue.path.split(separator: "/").map(String.init)
        if parts.first == "geometry", parts.count > 2, parts[1] == "rooms", let index = Int(parts[2]), project.geometry.rooms.indices.contains(index) {
            let room = project.geometry.rooms[index]
            if let id = focusEntityID, room.openings.contains(where: { $0.id == id }) { routeEditor(.opening(room.id, id)) }
            else { focusEntityID = room.id; routeEditor(.room(room.id)) }; return
        }
        if parts.first == "scenarios", parts.count > 1, let index = Int(parts[1]), project.scenarios.indices.contains(index) {
            store.selectedScenarioID = project.scenarios[index].id
            if parts.contains("envelope") || parts.contains("ventilation") || parts.contains("environment") || parts.contains("cost") {
                routeEditor(.conditions(project.scenarios[index].id)); return
            }
        }
        store.selection = .workspace; focusEntityID = issue.entityID ?? entityID(at: issue.path)
        if let id = focusEntityID { routeEditor(.object(id)) }
        else { store.presentedError = "此问题无法自动定位到单一字段：\(ValidationPresentation.fieldPath(issue.path))。请从使用条件或对象清单检查；原输入保留。" }
    }
}
private enum WorkspaceSheet: Hashable, Identifiable {
    case wizard, templates, object(UUID), room(UUID), opening(UUID, UUID), conditions(UUID), assumptions, issues, snapshot, identity, dailySettings, direction, capture
    var id: Self { self }
}
private struct ProjectNameView: View {
    @State var name: String
    let onApply: @MainActor (String) throws -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            EditorForm {
                EditorTextField(title: "项目名称", text: $name)
                Text("这是项目内部名称。文档文件名通过系统保存或重命名修改；方案名称在方案管理中修改。").font(.caption).foregroundStyle(.secondary)
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
        }.modifier(EditorSheetSize(compact: true))
    }
}
