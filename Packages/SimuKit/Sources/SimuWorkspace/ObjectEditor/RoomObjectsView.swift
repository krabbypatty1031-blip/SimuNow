import SwiftUI
import SimuCore
import SimuVisualization

private struct ObjectEditRequest: Identifiable {
    let selection: RoomPlanSelection
    let isNew: Bool
    var focus: EditorFocus = .init()
    var id: String { selection.id }
}
private struct RoomGeometryEditRequest: Identifiable {
    let target: RoomSceneSelectionTarget
    var id: String { String(describing: target) }
}
private struct ObjectOccupantRepairRequest: Identifiable { let id: UUID }
private struct ObjectMoveRequest: Identifiable {
    let selection: RoomPlanSelection
    let position: Position3D
    var id: String { selection.id }
}

/// Standalone editor. The owner commits the complete value as one undoable transaction.
public struct RoomObjectsView: View {
    public let project: ProjectDocument
    public let scenarioID: UUID
    public let registry: ModelRegistry
    public let focusEntityID: UUID?
    public let overlay: RoomSceneOverlay
    public let rendererCapability: RendererCapabilities
    public var selectedSceneKey: SceneObjectKey?
    public var onSelectionChange: @MainActor (SceneObjectKey?) -> Void
    @Binding private var inspectorPresented: Bool
    var requestedFocus: EditorFocus = .init()
    public let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    @State private var selection: RoomPlanSelection?
    @State private var sceneSelection: SceneObjectKey?
    @State private var geometryEditRequest: RoomGeometryEditRequest?
    @State private var editRequest: ObjectEditRequest?
    @State private var moveRequest: ObjectMoveRequest?
    @State private var occupantRepairRequest: ObjectOccupantRepairRequest?
    @State private var controlRepairRequest: ObjectOccupantRepairRequest?
    @State private var placing = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var search = ""
    @State private var showBrowser = false
    @FocusState private var searching: Bool
    public init(project: ProjectDocument, scenarioID: UUID, registry: ModelRegistry = .builtIn, focusEntityID: UUID? = nil, overlay: RoomSceneOverlay = .empty, rendererCapability: RendererCapabilities = .current,
                selectedSceneKey: SceneObjectKey? = nil, inspectorPresented: Binding<Bool> = .constant(true),
                onSelectionChange: @escaping @MainActor (SceneObjectKey?) -> Void = { _ in },
                focusField: String? = nil,
                onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.selectedSceneKey = selectedSceneKey; self.onSelectionChange = onSelectionChange; _inspectorPresented = inspectorPresented; requestedFocus = .init(entityID: focusEntityID, field: focusField)
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.focusEntityID = focusEntityID; self.overlay = overlay; self.rendererCapability = rendererCapability; self.onCommit = onCommit
    }
    private var input: ScenarioInputs? { project.scenarios.first { $0.id == scenarioID }?.inputs }
    private var room: Room? { project.geometry.rooms.first }
    private var roomBounds: GeometryBounds? {
        guard let room, let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry) else { return nil }
        return shape.geometryBounds()
    }
    private var canAdd: Bool {
        guard input != nil, let b = roomBounds else { return false }
        return [b.size.x, b.size.y, b.size.z].allSatisfy { $0.isFinite && $0 > 0 }
    }
    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 760 {
                    objectBrowser.frame(width: 220)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Menu { addButtons } label: { Label("添加对象", systemImage: "plus") }.disabled(!canAdd)
                        if let selection, !inspectorPresented {
                            Button("编辑属性", systemImage: "pencil") { edit(selection) }
                                .keyboardShortcut("e", modifiers: .command).disabled(editableParent(selection) == nil)
                        }
                        if geometry.size.width < 760 {
                            Button("对象清单", systemImage: "list.bullet") { showBrowser.toggle() }
                                .keyboardShortcut("f", modifiers: .command)
                                .popover(isPresented: $showBrowser) { objectBrowser.frame(width: 280, height: 420).onAppear { searching = true } }
                        }
                        Spacer()
                        if placing { Button("取消放置", role: .cancel) { placing = false } }
                    }.controlSize(.small)
                    RoomViewportContainer(project: project, scenarioID: scenarioID, registry: registry, capability: rendererCapability,
                        selection: sceneSelection, planSelection: selection, placing: placing, overlay: overlay,
                        onSelect: chooseScene, onPlace: place, canEdit: canEditScene, onEdit: editScene)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if placing {
                        Label("点击俯视图设置 X/Y；保持高度。家具按最小角放置。", systemImage: "cursorarrow.click")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .inspector(isPresented: $inspectorPresented) {
            selectionInspector.inspectorColumnWidth(min: 240, ideal: 280, max: 380)
        }
        #else
        .sheet(isPresented: $inspectorPresented) { NavigationStack { selectionInspector.navigationTitle("对象属性").toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { inspectorPresented = false } } } } }
        #endif
        .sheet(item: $geometryEditRequest) { request in
            NavigationStack {
                switch request.target {
                case .room(let id): RoomEditorView(project: project, roomID: id, registry: registry, onCommit: onCommit)
                case .opening(let roomID, let openingID): OpeningEditorView(project: project, roomID: roomID, openingID: openingID, registry: registry, onCommit: onCommit)
                case .object: Text("请从最新对象列表重新打开属性。")
                }
            }
            #if os(macOS)
            .modifier(EditorSheetSize())
            #endif
        }
        .sheet(item: $editRequest) { request in RoomObjectEditorView(project: project, scenarioID: scenarioID, selection: request.selection, isNew: request.isNew, registry: registry, onCommit: onCommit).environment(\.editorFocus, request.focus) }
        .sheet(item: $occupantRepairRequest) { request in
            if let input, let occupant = input.usage.occupants.first(where: { $0.id == request.id }) {
                ObjectOccupantRepairEditor(project: project, scenarioID: scenarioID, occupant: occupant, registry: registry, onCommit: onCommit)
            } else { ObjectUnavailableEditor() }
        }
        .sheet(item: $controlRepairRequest) { request in
            if let input, let control = input.controls.first(where: { $0.id == request.id }) {
                ObjectControlRepairEditor(project: project, scenarioID: scenarioID, control: control, registry: registry, onCommit: onCommit)
            } else { ObjectUnavailableEditor() }
        }
        .sheet(item: $moveRequest) { request in
            ObjectPositionEditor(project: project, scenarioID: scenarioID, selection: request.selection, position: request.position, registry: registry, onCommit: onCommit)
        }
        .confirmationDialog("删除所选对象？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除对象及相关引用", role: .destructive) { deleteSelection() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(selection?.kind == .seat ? "座位对应的人员记录会一起删除。" : selection?.kind == .hvac ? "空调的风口和对应控制会一起删除。" : selection?.kind == .furniture ? "此家具会从所有方案的共享几何中删除。" : "此操作可通过项目撤销恢复。")
        }
        .onAppear { if let selectedSceneKey { chooseScene(selectedSceneKey) }; focus(focusEntityID) }
        .onChange(of: selectedSceneKey) { _, key in if key != sceneSelection { chooseScene(key) } }
        .onChange(of: focusEntityID) { _, id in focus(id) }
        .onChange(of: project) { _, newValue in
            if let selection, !ObjectEditing.contains(selection, in: newValue, scenarioID: scenarioID) { self.selection = nil; placing = false }
            if let sceneSelection, RoomSceneSelectionAdapter.target(for: sceneSelection, project: newValue, scenarioID: scenarioID) == nil { self.sceneSelection = nil; onSelectionChange(nil) }
        }
        .onChange(of: scenarioID) { _, _ in selection = nil; sceneSelection = nil; onSelectionChange(nil); placing = false; editRequest = nil; moveRequest = nil; occupantRepairRequest = nil; controlRepairRequest = nil; geometryEditRequest = nil }
    }
    private func matches(_ name: String) -> Bool { search.isEmpty || name.localizedStandardContains(search) }
    private var objectBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("对象清单").font(.headline)
                Spacer()
                Button("查找", systemImage: "magnifyingglass") { searching = true }
                    .labelStyle(.iconOnly).keyboardShortcut("f", modifiers: .command)
            }
            TextField("搜索对象名称", text: $search).textFieldStyle(.roundedBorder).focused($searching)
                .accessibilityLabel("查找房间对象")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
            EditorDisclosure(title: "家具 · 共享 \(project.geometry.obstacles.count)", initiallyExpanded: true) {
                ForEach(project.geometry.obstacles.filter { matches($0.name) }, id: \.id) { obstacle in
                    objectRow(obstacle.name, selection: .init(kind: .furniture, objectID: obstacle.id))
                    if (try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry)) == nil {
                        Text("\(obstacle.shape.kind) v\(obstacle.shape.payloadVersion)：当前类型只读，原数据保留。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if project.geometry.obstacles.isEmpty { Text("尚无家具").foregroundStyle(.secondary) }
            }
            if let input {
                EditorDisclosure(title: "座位与关注点 \(input.usage.seats.count)", initiallyExpanded: true) {
                    ForEach(input.usage.seats.filter { matches($0.name + " 座位 采样点 人员") }, id: \.id) { seat in
                        EditorDisclosure(title: seat.name, entityID: seat.id, initiallyExpanded: !search.isEmpty || selection?.objectID == seat.id || seat.samples.contains { $0.id == selection?.objectID }) {
                        objectRow(seat.name, selection: .init(kind: .seat, objectID: seat.id))
                        ForEach(Array(seat.samples.enumerated()), id: \.element.id) { index, sample in
                            objectRow("\(seat.name) / 采样点 \(index + 1)", selection: .init(kind: .sample, objectID: sample.id))
                        }
                        let occupied = input.usage.occupants.contains { $0.seatID == seat.id }
                        Text(occupied ? "有人使用" : "未配置人员").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if input.usage.seats.isEmpty { Text("尚无座位").foregroundStyle(.secondary) }
                }
                if !input.usage.occupants.filter({ occupant in !input.usage.seats.contains { $0.id == occupant.seatID } }).isEmpty {
                    Section("待修复的人员关联") {
                        ForEach(input.usage.occupants.filter { occupant in !input.usage.seats.contains { $0.id == occupant.seatID } }, id: \.id) { occupant in
                            Text("人员记录引用了不存在的座位：\(occupant.seatID.uuidString)").font(.caption).foregroundStyle(.orange)
                            Button("选择有效座位并修复") { occupantRepairRequest = .init(id: occupant.id) }
                        }
                    }
                }
                Section("设备热源 · 当前方案") {
                    ForEach(input.usage.equipment.filter { matches(InputDisplay.equipment($0.id) + " 设备") }, id: \.id) { item in
                        objectRow(InputDisplay.equipment(item.id), selection: .init(kind: .equipment, objectID: item.id))
                    }
                    if input.usage.equipment.isEmpty { Text("尚无设备热源").foregroundStyle(.secondary) }
                }
                EditorDisclosure(title: "空调与风口 \(input.hvac.count)", initiallyExpanded: true) {
                    ForEach(input.hvac.filter { matches($0.name + " 空调 送风口 回风口 温控测点") }, id: \.id) { device in
                        EditorDisclosure(title: device.name, entityID: device.id, initiallyExpanded: !search.isEmpty || selection?.objectID == device.id || device.ports.contains { $0.id == selection?.objectID } || input.controls.contains { $0.deviceID == device.id && $0.id == selection?.objectID }) {
                        objectRow(device.name, selection: .init(kind: .hvac, objectID: device.id))
                        if (try? device.definition.resolved(as: SingleSplit.self, registry: registry)) == nil {
                            Text("\(device.definition.kind) v\(device.definition.payloadVersion)：当前类型只读，原数据保留。").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(device.ports.enumerated()), id: \.element.id) { index, port in
                            objectRow("\(device.name) / \(port.role == .supply ? "送风口" : "回风口") \(index + 1)", selection: .init(kind: .port, objectID: port.id))
                        }
                        ForEach(input.controls.filter { $0.deviceID == device.id }, id: \.id) { control in
                            objectRow("\(device.name) / 温控测点", selection: .init(kind: .control, objectID: control.id))
                        }
                    }
                    }
                    if input.hvac.isEmpty { Text("尚无空调").foregroundStyle(.secondary) }
                    ForEach(input.controls.filter { control in !input.hvac.contains { $0.id == control.deviceID } }, id: \.id) { control in
                        Text("温控记录引用了不存在的空调：\(control.deviceID.uuidString)").font(.caption).foregroundStyle(.orange)
                        Button("选择有效空调并修复温控") { controlRepairRequest = .init(id: control.id) }
                    }
                }
            }

                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .task(id: selection) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if let selection { proxy.scrollTo(selection.id, anchor: .center) }
                }
            }
        }.padding(12).frame(maxHeight: .infinity)
        .environment(\.editorFocus, EditorFocus(entityID: selection?.objectID))
    }
    private var selectionInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let key = sceneSelection {
                    Text(FieldNavigation.objectName(project: project, path: "", entityID: key.modelID)).font(.headline)
                    if let selection {
                        Label(selection.kind.title, systemImage: "scope")
                        Label(selection.kind == .furniture ? "全部方案共享" : "仅当前方案", systemImage: "square.stack.3d.up").font(.caption)
                        if selection.kind == .furniture { Text("修改会使相关方案的预览过期。").font(.caption).foregroundStyle(.secondary) }
                        if let p = ObjectEditing.position(of: selection, in: project, scenarioID: scenarioID, registry: registry) {
                            LabeledContent("X · 横向", value: p.x.formatted() + " m")
                            LabeledContent("Y · 纵向", value: p.y.formatted() + " m")
                            LabeledContent("Z · 高度", value: p.z.formatted() + " m")
                        }
                        if let input, let port = input.hvac.flatMap(\.ports).first(where: { $0.id == selection.objectID }) {
                            let angles = AirflowDirection.angles(port.direction)
                            DirectionPreview(yaw: String(angles.yaw), pitch: String(angles.pitch))
                        }
                        Button("编辑属性", systemImage: "pencil") { edit(selection) }
                            .buttonStyle(.borderedProminent).disabled(editableParent(selection) == nil)
                            .keyboardShortcut("e", modifiers: .command)
                        Menu("位置与删除") { selectionActions(selection) }
                        if overlay.paths.contains(where: { $0.hitEntityID == selection.objectID }) {
                            Label("此对象遮挡了当前假设路径", systemImage: "exclamationmark.triangle").font(.caption)
                        }
                    } else if let target = RoomSceneSelectionAdapter.target(for: key, project: project, scenarioID: scenarioID) {
                        Label("房间与门窗 · 全部方案共享", systemImage: "square.stack.3d.up").font(.caption)
                        Button("编辑属性") { editScene(target) }.disabled(!canEditScene(target))
                    }
                    Button("清除选择") { chooseScene(nil) }.controlSize(.small)
                } else {
                    Text("选择对象查看属性").font(.headline)
                    Text("点击画布或对象清单。属性、位置和遮挡提示将在此同步显示。")
                        .font(.callout).foregroundStyle(.secondary)
                    LabeledContent("房间", value: room?.name ?? "未创建")
                    LabeledContent("家具", value: "\(project.geometry.obstacles.count)")
                    LabeledContent("座位", value: "\(input?.usage.seats.count ?? 0)")
                    LabeledContent("空调", value: "\(input?.hvac.count ?? 0)")
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var addButtons: some View {
        Button("家具", systemImage: "square.fill") { add(.furniture) }
        Button("座位", systemImage: "chair") { add(.seat) }
        Button("热源", systemImage: "flame") { add(.equipment) }
        Button("空调", systemImage: "air.conditioner.horizontal") { add(.hvac) }
    }
    @ViewBuilder private func selectionActions(_ selection: RoomPlanSelection) -> some View {
        Button(placing ? "取消放置" : "点击放置") { placing.toggle() }.disabled(!canMove(selection))
        Button("调整位置") {
            if let p = ObjectEditing.position(of: selection, in: project, scenarioID: scenarioID, registry: registry) {
                moveRequest = .init(selection: selection, position: p)
            }
        }.disabled(!canMove(selection))
        Button("删除", role: .destructive) { confirmDelete = true }
    }
    private func focus(_ id: UUID?) {
        guard let id, let input else { return }
        let candidates: [RoomPlanSelection] = project.geometry.obstacles.map { .init(kind: .furniture, objectID: $0.id) }
            + input.usage.seats.map { .init(kind: .seat, objectID: $0.id) }
            + input.usage.seats.flatMap(\.samples).map { .init(kind: .sample, objectID: $0.id) }
            + input.usage.equipment.map { .init(kind: .equipment, objectID: $0.id) }
            + input.hvac.map { .init(kind: .hvac, objectID: $0.id) }
            + input.hvac.flatMap(\.ports).map { .init(kind: .port, objectID: $0.id) }
            + input.controls.map { .init(kind: .control, objectID: $0.id) }
        if let match = candidates.first(where: { $0.objectID == id }) { chooseScene(.init(match)); inspectorPresented = true }
        else if let occupant = input.usage.occupants.first(where: { $0.id == id }) {
            if input.usage.seats.contains(where: { $0.id == occupant.seatID }) {
                chooseScene(.init(category: .occupant, modelID: occupant.id))
            } else {
                selection = nil; placing = false
                error = "人员记录引用了不存在的座位 \(occupant.seatID.uuidString)。请使用待修复人员关联表单。"
            }
        } else { error = "当前方案中找不到问题对象 \(id.uuidString)。请切换到该对象所属方案。" }
    }
    private func objectRow(_ name: String, selection item: RoomPlanSelection) -> some View {
        HStack {
            Button { chooseScene(.init(item)) } label: {
                Label(name, systemImage: selection == item ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)

        }
        .id(item.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name + "，" + item.kind.title)
        .help(name)
    }
    private func chooseScene(_ key: SceneObjectKey?) {
        sceneSelection = key; onSelectionChange(key); placing = false; error = nil
        if let key, let target = RoomSceneSelectionAdapter.target(for: key, project: project, scenarioID: scenarioID), case .object(let item) = target { selection = item }
        else { selection = nil }
    }
    private func canEditScene(_ target: RoomSceneSelectionTarget) -> Bool {
        switch target {
        case .object(let item): return editableParent(item) != nil
        case .room(let id): return project.geometry.rooms.first(where: { $0.id == id }).flatMap { try? $0.shape.resolved(as: RectangularRoom.self, registry: registry) } != nil
        case .opening(let roomID, let openingID): return project.geometry.rooms.contains { $0.id == roomID && $0.openings.contains { $0.id == openingID } }
        }
    }
    private func editScene(_ target: RoomSceneSelectionTarget) {
        guard canEditScene(target) else { return }
        placing = false
        switch target { case .object(let item): edit(item); case .room, .opening: geometryEditRequest = .init(target: target) }
    }
    private func editableParent(_ item: RoomPlanSelection) -> RoomPlanSelection? {
        guard let input else { return nil }
        switch item.kind {
        case .furniture:
            guard let value = project.geometry.obstacles.first(where: { $0.id == item.objectID }),
                  (try? value.shape.resolved(as: BoxObstacle.self, registry: registry)) != nil else { return nil }
            return item
        case .hvac:
            guard let value = input.hvac.first(where: { $0.id == item.objectID }),
                  (try? value.definition.resolved(as: SingleSplit.self, registry: registry)) != nil else { return nil }
            return item
        case .port:
            guard let device = input.hvac.first(where: { $0.ports.contains { $0.id == item.objectID } }) else { return nil }
            return editableParent(.init(kind: .hvac, objectID: device.id))
        case .control:
            guard let control = input.controls.first(where: { $0.id == item.objectID }) else { return nil }
            return editableParent(.init(kind: .hvac, objectID: control.deviceID))
        case .sample:
            guard let seat = input.usage.seats.first(where: { $0.samples.contains { $0.id == item.objectID } }) else { return nil }
            return .init(kind: .seat, objectID: seat.id)
        case .seat: return input.usage.seats.contains { $0.id == item.objectID } ? item : nil
        case .equipment: return input.usage.equipment.contains { $0.id == item.objectID } ? item : nil
        }
    }
    private func canMove(_ item: RoomPlanSelection) -> Bool {
        canAdd && editableParent(item) != nil && ObjectEditing.position(of: item, in: project, scenarioID: scenarioID, registry: registry) != nil
    }
    private func edit(_ item: RoomPlanSelection) {
        guard let parent = editableParent(item) else { return }
        placing = false; editRequest = .init(selection: parent, isNew: false, focus: .init(entityID: item.objectID, field: requestedFocus.field))
    }
    private func add(_ kind: RoomPlanObjectKind) {
        placing = false; editRequest = .init(selection: .init(kind: kind, objectID: UUID()), isNew: true)
    }
    private func place(_ clicked: Position3D) {
        guard let selection, let old = ObjectEditing.position(of: selection, in: project, scenarioID: scenarioID, registry: registry) else { return }
        var candidate = project
        do {
            try ObjectEditing.move(selection, to: .init(x: clicked.x, y: clicked.y, z: old.z), scenarioID: scenarioID, project: &candidate, registry: registry)
            try onCommit(candidate, "俯视放置对象"); error = nil; placing = false
        } catch { self.error = error.localizedDescription }
    }
    private func deleteSelection() {
        guard let selection else { return }
        var candidate = project
        do {
            try ObjectEditing.delete(selection, scenarioID: scenarioID, project: &candidate, registry: registry)
            try onCommit(candidate, "删除对象与相关引用"); self.selection = nil; placing = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct RoomObjectEditorView: View {
    let project: ProjectDocument
    let scenarioID: UUID
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    private let request: ObjectEditRequest
    init(project: ProjectDocument, scenarioID: UUID, selection: RoomPlanSelection, isNew: Bool = false,
         registry: ModelRegistry, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.onCommit = onCommit
        self.request = .init(selection: selection, isNew: isNew)
    }
    private var input: ScenarioInputs? { project.scenarios.first { $0.id == scenarioID }?.inputs }
    private var room: Room? { project.geometry.rooms.first }
    private var roomBounds: GeometryBounds? {
        guard let room, let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry) else { return nil }
        return shape.geometryBounds()
    }
    @ViewBuilder var body: some View {
        if !request.isNew, !ObjectEditing.contains(request.selection, in: project, scenarioID: scenarioID) {
            ObjectUnavailableEditor()
        } else if let room, let input, let bounds = roomBounds {
            let centre = Position3D(x: bounds.origin.x + bounds.size.x / 2, y: bounds.origin.y + bounds.size.y / 2, z: bounds.origin.z + bounds.size.z / 2)
            switch request.selection.kind {
            case .furniture:
                if let obstacle = project.geometry.obstacles.first(where: { $0.id == request.selection.objectID }), let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry) {
                    FurnitureEditorSheet(project: project, value: .init(obstacle, box: box), registry: registry, isNew: false, onCommit: onCommit)
                } else if request.isNew {
                    if let record = try? ExtensionRecord(BoxObstacle(origin: .init(x: centre.x, y: centre.y, z: 0), dimensions: .init(width: .unknown(reason: "待输入家具宽度"), depth: .unknown(reason: "待输入家具深度"), height: .unknown(reason: "待输入家具高度")))), let box = try? record.resolved(as: BoxObstacle.self, registry: registry) {
                        FurnitureEditorSheet(project: project, value: .init(.init(id: request.selection.objectID, roomID: room.id, name: "家具", shape: record), box: box), registry: registry, isNew: true, onCommit: onCommit)
                    } else { ObjectUnavailableEditor() }
                } else { ObjectUnavailableEditor() }
            case .seat:
                let seat = input.usage.seats.first { $0.id == request.selection.objectID } ?? .init(id: request.selection.objectID, roomID: room.id, name: "座位", position: .init(x: centre.x, y: centre.y, z: 0), samples: [.init(id: UUID(), position: centre)])
                SeatEditorSheet(project: project, scenarioID: scenarioID, value: .init(seat, occupant: input.usage.occupants.first { $0.seatID == seat.id }), registry: registry, isNew: request.isNew, onCommit: onCommit)
            case .equipment:
                let item = input.usage.equipment.first { $0.id == request.selection.objectID } ?? .init(id: request.selection.objectID, roomID: room.id, position: centre, heat: ObjectEditing.unknownHeat(), schedule: .init())
                EquipmentEditorSheet(project: project, scenarioID: scenarioID, value: .init(item), registry: registry, isNew: request.isNew, onCommit: onCommit)
            case .hvac:
                if let device = input.hvac.first(where: { $0.id == request.selection.objectID }), let split = try? device.definition.resolved(as: SingleSplit.self, registry: registry) {
                    DeviceEditorSheet(project: project, scenarioID: scenarioID, value: .init(device, split: split, control: input.controls.first { $0.deviceID == device.id }, initialSensor: centre), registry: registry, isNew: false, onCommit: onCommit)
                } else if request.isNew {
                    let split = SingleSplit(coolingCapacity: .unknown(reason: "待提供制冷性能依据"), electricalPower: .unknown(reason: "待提供电功率依据"), cop: .unknown(reason: "待提供 COP 依据"))
                    if let record = try? ExtensionRecord(split) {
                        let device = HVACDevice(id: request.selection.objectID, roomID: room.id, name: "分体空调", position: centre, definition: record, supplyTemperature: .unknown(reason: "待提供送风温度"))
                        DeviceEditorSheet(project: project, scenarioID: scenarioID, value: .init(device, split: split, control: nil, initialSensor: centre), registry: registry, isNew: true, onCommit: onCommit)
                    } else { ObjectUnavailableEditor() }
                } else { ObjectUnavailableEditor() }
            case .sample, .port, .control: ObjectUnavailableEditor()
            }
        } else { ObjectUnavailableEditor() }
    }
}

private struct ObjectUnavailableEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ContentUnavailableView("编辑对象已改变", systemImage: "exclamationmark.circle",
                description: Text("所选对象已被删除、类型已改变，或所属房间已不可编辑。请关闭此表单并从最新项目重新选择。"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
private struct ObjectPositionEditor: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let scenarioID: UUID
    let selection: RoomPlanSelection
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    let original: ObjectPositionDraft
    @State private var draft: ObjectPositionDraft
    init(project: ProjectDocument, scenarioID: UUID, selection: RoomPlanSelection, position: Position3D, registry: ModelRegistry, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.selection = selection; self.registry = registry; self.onCommit = onCommit
        original = .init(position); _draft = .init(initialValue: .init(position)); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "调整位置", hasChanges: draft != original, compact: true, onApply: apply) {
            Section("绝对位置") {
                ObjectPositionFields(title: selection.kind == .furniture ? "盒体最小角" : "计算坐标", draft: $draft)
                Text("座位移动会同步平移采样点；设备移动会同步平移风口，温控测点保持原位。独立选择采样点、风口或温控测点时，只修改所选点。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        var next = project
        try ObjectEditing.move(selection, to: draft.position(), scenarioID: scenarioID, project: &next, registry: registry)
        try onCommit(next, "修改对象数值位置")
    }
}

private struct ObjectOccupantRepairEditor: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let scenarioID: UUID
    let registry: ModelRegistry
    let occupant: Occupant
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    @State private var selectedSeat: UUID?
    @State private var draft: OccupantEditDraft
    let original: OccupantEditDraft
    init(project: ProjectDocument, scenarioID: UUID, occupant: Occupant, registry: ModelRegistry, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.occupant = occupant; self.registry = registry; self.onCommit = onCommit
        original = .init(occupant); _draft = .init(initialValue: .init(occupant)); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "修复人员关联", hasChanges: selectedSeat != nil || draft != original, onApply: apply) {
            Section("关联座位") {
                Text("当前人员记录的座位已不存在。选择有效座位会保留人员身份、热量和使用条件。").font(.caption).foregroundStyle(.secondary)
                Picker("新座位", selection: $selectedSeat) {
                    Text("请选择").tag(Optional<UUID>.none)
                    ForEach(project.scenarios.first(where: { $0.id == scenarioID })?.inputs.usage.seats ?? [], id: \.id) { seat in
                        Text(seat.name).tag(Optional(seat.id))
                    }
                }
                Text("每个座位只允许一条人员记录；已有人员的座位不可重复关联。").font(.caption).foregroundStyle(.secondary)
            }
            Section("人员参数") {
                ObjectParameterField(title: "活动水平", unit: "met", draft: $draft.activity)
                ObjectParameterField(title: "衣着热阻", unit: "clo", draft: $draft.clothing)
                ObjectHeatFields(draft: $draft.heat)
            }
            Section("使用时间表") { ObjectScheduleFields(draft: $draft.schedule) }
        }
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        guard let selectedSeat, let value = try draft.value(seatID: selectedSeat) else { throw ProjectDataError.contract("请选择一个有效座位。") }
        var next = project
        try ObjectEditing.upsertOccupant(value, scenarioID: scenarioID, project: &next, registry: registry)
        try onCommit(next, "修复人员关联")
    }
}

private struct ObjectControlRepairEditor: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let scenarioID: UUID
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    @State private var selectedDevice: UUID?
    @State private var draft: ControlEditDraft
    let original: ControlEditDraft
    init(project: ProjectDocument, scenarioID: UUID, control: Control, registry: ModelRegistry, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.onCommit = onCommit
        original = .init(control, initialSensor: control.sensorPosition); _draft = .init(initialValue: original); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "修复温控关联", hasChanges: selectedDevice != nil || draft != original, onApply: apply) {
            Section("关联空调") {
                Text("当前温控记录的空调已不存在。选择有效空调会保留控制身份、温控设定和时间表。").font(.caption).foregroundStyle(.secondary)
                Picker("新空调", selection: $selectedDevice) {
                    Text("请选择").tag(Optional<UUID>.none)
                    ForEach(project.scenarios.first(where: { $0.id == scenarioID })?.inputs.hvac ?? [], id: \.id) { device in Text(device.name).tag(Optional(device.id)) }
                }
                Text("每台空调只允许一条温控记录；已有温控的设备不可重复关联。").font(.caption).foregroundStyle(.secondary)
            }
            Section("温控") {
                ObjectParameterField(title: "设定温度", unit: "°C", draft: $draft.setpoint)
                ObjectPositionFields(title: "温控测点绝对位置", draft: $draft.sensor)
            }
            Section("运行时间表") { ObjectScheduleFields(draft: $draft.schedule) }
        }
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        guard let selectedDevice, let value = try draft.value(deviceID: selectedDevice) else { throw ProjectDataError.contract("请选择一个有效空调。") }
        var next = project
        try ObjectEditing.upsertControl(value, scenarioID: scenarioID, project: &next, registry: registry)
        try onCommit(next, "修复温控关联")
    }
}
