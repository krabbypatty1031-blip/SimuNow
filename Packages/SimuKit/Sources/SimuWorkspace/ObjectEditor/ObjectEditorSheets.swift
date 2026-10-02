import SwiftUI
import SimuCore
import SimuVisualization

struct ObjectEditorScaffold<Content: View>: View {
    let title: String
    let hasChanges: Bool
    let onApply: @MainActor () throws -> Void
    @ViewBuilder let content: () -> Content
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDiscard = false
    var body: some View {
        NavigationStack {
            Form {
                content()
                if let error { Section("无法应用") { Text(error).foregroundStyle(.red).textSelection(.enabled) } }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if hasChanges { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { do { try onApply(); dismiss() } catch { self.error = error.localizedDescription } }
                }
            }
            .confirmationDialog("放弃尚未应用的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasChanges)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 560, minHeight: 540, idealHeight: 760)
        #endif
    }
}
struct FurnitureEditorSheet: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    let original: FurnitureEditDraft
    let isNew: Bool
    @State private var draft: FurnitureEditDraft
    init(project: ProjectDocument, value: FurnitureEditDraft, registry: ModelRegistry, isNew: Bool, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.registry = registry; self.onCommit = onCommit; original = value; self.isNew = isNew; _draft = .init(initialValue: value); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "盒体家具", hasChanges: isNew || draft != original, onApply: apply) {
            Section("共享几何") {
                Text("家具属于项目共享几何。修改将检查全部方案的座位、采样点、风口及热源。").font(.caption).foregroundStyle(.secondary)
                TextField("名称", text: $draft.name)
                ObjectRoomPicker(project: project, roomID: $draft.roomID)
                ObjectPositionFields(title: "盒体最小角", draft: $draft.origin)
            }
            Section("尺寸（轴对齐）") {
                ObjectParameterField(title: "宽度 X", unit: "m", draft: $draft.width)
                ObjectParameterField(title: "深度 Y", unit: "m", draft: $draft.depth)
                ObjectParameterField(title: "高度 Z", unit: "m", draft: $draft.height)
                Text("当前模型为轴对齐盒体。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        var next = project
        try ObjectEditing.upsertFurniture(draft.value(), project: &next, registry: registry)
        try onCommit(next, isNew ? "添加家具" : "修改家具")
    }
}
struct SeatEditorSheet: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let scenarioID: UUID
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    let original: SeatEditDraft
    let isNew: Bool
    @State private var draft: SeatEditDraft
    init(project: ProjectDocument, scenarioID: UUID, value: SeatEditDraft, registry: ModelRegistry, isNew: Bool, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.onCommit = onCommit; original = value; self.isNew = isNew; _draft = .init(initialValue: value); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "座位、采样点与人员", hasChanges: isNew || draft != original, onApply: apply) {
            Section("座位") {
                TextField("名称", text: $draft.name)
                ObjectRoomPicker(project: project, roomID: $draft.roomID)
                ObjectPositionFields(title: "座位位置", draft: $draft.position)
                Text("移动座位时采样点随之平移，各自身份保持不变。人员与座位、采样点分别建模。").font(.caption).foregroundStyle(.secondary)
            }
            Section("采样点") {
                ForEach($draft.samples) { $sample in
                    DisclosureGroup("采样点 \((draft.samples.firstIndex { $0.id == sample.id } ?? 0) + 1)") {
                        ObjectPositionFields(title: "相对座位的偏移", draft: $sample.offset)
                        if let origin = try? draft.position.position(), let value = try? sample.value(relativeTo: origin) {
                            Text("绝对位置：X \(value.position.x.formatted())，Y \(value.position.y.formatted())，Z \(value.position.z.formatted()) m").font(.caption)
                        }
                        Button("删除采样点", role: .destructive) { draft.samples.removeAll { $0.id == sample.id } }
                    }
                }
                Button("添加采样点", systemImage: "plus") {
                    draft.samples.append(.init(.init(id: UUID(), position: .init(x: 0, y: 0, z: 0)), relativeTo: .init(x: 0, y: 0, z: 0)))
                }
                if draft.samples.isEmpty { Text("缺少有效采样点，当前座位不能进入计算评价。").foregroundStyle(.orange) }
            }
            Section("人员") {
                Toggle("该座位有人员记录", isOn: $draft.occupant.enabled)
                if draft.occupant.enabled {
                    ObjectParameterField(title: "活动水平", unit: "met", draft: $draft.occupant.activity)
                    ObjectParameterField(title: "衣着热阻", unit: "clo", draft: $draft.occupant.clothing)
                    ObjectHeatFields(draft: $draft.occupant.heat)
                }
            }
            if draft.occupant.enabled { Section("人员使用时间表") { ObjectScheduleFields(draft: $draft.occupant.schedule) } }
        }
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        let seat = try draft.value(), occupant = try draft.occupant.value(seatID: draft.id)
        var next = project
        try ObjectEditing.upsertSeat(seat, occupant: occupant, scenarioID: scenarioID, project: &next, registry: registry)
        try onCommit(next, isNew ? "添加座位" : "修改座位与人员")
    }
}
struct EquipmentEditorSheet: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let scenarioID: UUID
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    let original: EquipmentEditDraft
    let isNew: Bool
    @State private var draft: EquipmentEditDraft
    init(project: ProjectDocument, scenarioID: UUID, value: EquipmentEditDraft, registry: ModelRegistry, isNew: Bool, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.onCommit = onCommit; original = value; self.isNew = isNew; _draft = .init(initialValue: value); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "设备热源", hasChanges: isNew || draft != original, onApply: apply) {
            Section("热源位置") {
                ObjectRoomPicker(project: project, roomID: $draft.roomID)
                ObjectPositionFields(title: "流体域内的点位", draft: $draft.position)
                Text("设备热源点与家具实体几何分开。该点必须位于房间内部并避开实体家具。").font(.caption).foregroundStyle(.secondary)
            }
            Section("热量") { ObjectHeatFields(draft: $draft.heat) }
            Section("使用时间表") { ObjectScheduleFields(draft: $draft.schedule) }
        }
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        var next = project
        try ObjectEditing.upsertEquipment(draft.value(), scenarioID: scenarioID, project: &next, registry: registry)
        try onCommit(next, isNew ? "添加设备热源" : "修改设备热源")
    }
}
struct DeviceEditorSheet: View {
    let project: ProjectDocument
    @State private var baseProject: ProjectDocument
    let scenarioID: UUID
    let registry: ModelRegistry
    let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    let original: DeviceEditDraft
    let isNew: Bool
    @State private var draft: DeviceEditDraft
    @State private var derivationError: String?
    init(project: ProjectDocument, scenarioID: UUID, value: DeviceEditDraft, registry: ModelRegistry, isNew: Bool, onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.onCommit = onCommit; original = value; self.isNew = isNew; _draft = .init(initialValue: value); _baseProject = .init(initialValue: project)
    }
    var body: some View {
        ObjectEditorScaffold(title: "分体空调、风口与控制", hasChanges: isNew || draft != original, onApply: apply) {
            Section("设备点位") {
                TextField("名称", text: $draft.name)
                ObjectRoomPicker(project: project, roomID: $draft.roomID)
                ObjectPositionFields(title: "室内机位置", draft: $draft.position)
                Text("移动设备时风口随之平移，温控测点保持原位。当前模型只含设备点位，没有机身尺寸或机身碰撞体。").font(.caption).foregroundStyle(.secondary)
            }
            Section("额定性能与送风状态") {
                ObjectParameterField(title: "制冷量", unit: "W", draft: $draft.capacity)
                ObjectParameterField(title: "电功率", unit: "W", draft: $draft.electricalPower)
                ObjectParameterField(title: "COP", unit: "COP", draft: $draft.cop)
                ObjectParameterField(title: "送风温度", unit: "°C", draft: $draft.supplyTemperature)
                Text("额定制冷量、电功率、COP、运行送风温度和温控设定分别保存。循环风口与室外新风分开。").font(.caption).foregroundStyle(.secondary)
            }
            Section("送回风口") {
                ForEach($draft.ports) { $port in
                    DisclosureGroup("\(port.role == .supply ? "送风口" : "回风口") \((draft.ports.firstIndex { $0.id == port.id } ?? 0) + 1)") {
                        Picker("作用", selection: $port.role) {
                            Text("送风").tag(PortRole.supply)
                            Text("回风").tag(PortRole.return)
                        }
                        ObjectPositionFields(title: "相对室内机的偏移", draft: $port.offset)
                        if let origin = try? draft.position.position(), let value = try? port.value(relativeTo: origin) {
                            Text("绝对位置：X \(value.position.x.formatted())，Y \(value.position.y.formatted())，Z \(value.position.z.formatted()) m").font(.caption)
                        }
                        objectTextField("水平角（°，+X 向 +Y）", text: $port.yaw)
                        objectTextField("俯仰角（°，水平向 +Z）", text: $port.pitch)
                        Button("按角度单位化方向") { port.rebuildDirection = true }
                        Text(port.role == .supply ? "送风向量表示气流从风口进入房间的方向。" : "回风向量表示气流从房间进入室内机的方向。").font(.caption).foregroundStyle(.secondary)
                        ObjectParameterField(title: "有效面积", unit: "m²", draft: $port.area)
                        ObjectParameterField(title: "体积流量", unit: "m³/s", draft: $port.flow)
                        ObjectParameterField(title: "风速", unit: "m/s", draft: $port.speed)
                        ObjectParameterField(title: "空气密度", unit: "kg/m³", draft: $port.density)
                        Button("由风量 ÷ 面积推导风速") {
                            do { try port.deriveSpeed(); derivationError = nil } catch { derivationError = error.localizedDescription }
                        }
                        Button("删除风口", role: .destructive) { draft.ports.removeAll { $0.id == port.id } }
                    }
                }
                HStack {
                    Button("添加送风口") { addPort(.supply) }
                    Button("添加回风口") { addPort(.return) }
                }
                if let derivationError { Text(derivationError).foregroundStyle(.red) }
                Text("已知面积 × 风速应等于风量；不一致时拒绝应用。质量平衡和模型完整性会单独列为计算准备问题。").font(.caption).foregroundStyle(.secondary)
            }
            Section("控制") {
                Toggle("配置温控", isOn: $draft.control.enabled)
                if draft.control.enabled {
                    ObjectParameterField(title: "设定温度", unit: "°C", draft: $draft.control.setpoint)
                    ObjectPositionFields(title: "温控测点绝对位置", draft: $draft.control.sensor)
                }
            }
            if draft.control.enabled { Section("温控运行时间表") { ObjectScheduleFields(draft: $draft.control.schedule) } }
        }
    }
    private func addPort(_ role: PortRole) {
        let direction = Direction3D(x: role == .supply ? 1 : -1, y: 0, z: 0)
        let port = AirPort(id: UUID(), role: role, position: .init(x: 0, y: 0, z: 0), direction: direction,
                           area: .unknown(reason: "待提供风口面积"), volumeFlow: .unknown(reason: "待提供循环风量"), speed: .unknown(reason: "待提供风速"), density: .unknown(reason: "待提供空气密度依据"))
        draft.ports.append(.init(port, relativeTo: .init(x: 0, y: 0, z: 0)))
    }
    private func apply() throws {
        try ObjectEditing.requireCurrentProject(base: baseProject, current: project)
        let device = try draft.value(), control = try draft.control.value(deviceID: draft.id)
        var next = project
        try ObjectEditing.upsertDevice(device, control: control, scenarioID: scenarioID, project: &next, registry: registry)
        try onCommit(next, isNew ? "添加空调" : "修改空调与控制")
    }
}
