import SwiftUI
import SimuCore
import SimuVisualization
import SimuSimulation

@MainActor
public struct DailySettingsView: View {
    let store: WorkspaceStore
    let onRoom: (UUID) -> Void
    let onAdvanced: () -> Void
    let onObject: (UUID) -> Void
    @State private var editingDirection = false
    public init(store: WorkspaceStore, onRoom: @escaping (UUID) -> Void, onAdvanced: @escaping () -> Void, onObject: @escaping (UUID) -> Void) {
        self.store = store; self.onRoom = onRoom; self.onAdvanced = onAdvanced; self.onObject = onObject
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("先看风向，再比较调整", systemImage: "house.and.flag").font(.headline)
            Text("只需房间尺寸、出风口位置与方向、关注位置。墙体热工、COP 和天气可稍后补充。")
                .font(.callout).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            Text("家具和房间几何由全部方案共享；比较不同家具布局请另存项目。设定温度与运行送风温度是两个输入，未知时保持未知。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $editingDirection) {
            if let project = store.project, let scenario = store.currentScenario {
                DailyDirectionEditor(project: project, scenario: scenario) { candidate in
                    guard store.project == project, store.selectedScenarioID == scenario.id else { throw PreviewConfigurationEditingError.staleDraft }
                    try store.replaceProject(candidate, actionName: "调整送风方向")
                }
            }
        }
    }
    @ViewBuilder private var actions: some View {
        if let room = store.project?.geometry.rooms.first {
            Button("1 · 房间尺寸") { onRoom(room.id) }
        }
        if let device = store.currentScenario?.inputs.hvac.first { Button("2 · 设备与风口") { onObject(device.id) } }
        Button("3 · 调整送风方向") { editingDirection = true }
            .disabled(store.currentScenario?.inputs.hvac.contains(where: { $0.ports.contains { $0.role == .supply } }) != true)
        if let seat = store.currentScenario?.inputs.usage.seats.first { Button("4 · 关注位置") { onObject(seat.id) } }
        Button("5 · 比较方案") { store.selection = .scenarios }
        Button("高级使用条件", action: onAdvanced)
    }
}

@MainActor struct DailyDirectionEditor: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    let project: ProjectDocument
    let scenario: Scenario
    let onCommit: (ProjectDocument) throws -> Void
    @State private var portID: UUID?
    @State private var yaw = 0.0
    @State private var pitch = 0.0
    @State private var error: String?
    init(project: ProjectDocument, scenario: Scenario, onCommit: @escaping (ProjectDocument) throws -> Void) {
        self.project = project; self.scenario = scenario; self.onCommit = onCommit
    }
    private var ports: [AirPort] { scenario.inputs.hvac.flatMap { $0.ports.filter { $0.role == .supply } } }
    var body: some View {
        NavigationStack {
            Form {
                Section("出风口") {
                    Picker("调整的送风口", selection: $portID) {
                        ForEach(scenario.inputs.hvac, id: \.id) { device in
                            ForEach(device.ports.filter { $0.role == .supply }, id: \.id) { port in
                                Text("\(device.name) · \(port.id.uuidString.prefix(6))").tag(Optional(port.id))
                            }
                        }
                    }
                    TextField("水平角 · °", value: $yaw, format: .number)
                    Slider(value: $yaw, in: -180...180) { Text("水平角 · °") }
                    TextField("俯仰角 · °", value: $pitch, format: .number)
                    Slider(value: $pitch, in: -90...90) { Text("俯仰角 · °") }
                    Text("水平角从 +X 朝 +Y；俯仰角从水平朝 +Z。只调整方向，不改变风量、送风温度或实际风档。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle("调整送风方向")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("应用调整") { apply() }.disabled(portID == nil) }
            }
        }
        .onAppear { portID = ports.first?.id; loadAngles() }
        .onChange(of: portID) { _, _ in loadAngles() }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 360)
        #endif
    }
    private func loadAngles() {
        guard let port = ports.first(where: { $0.id == portID }) else { return }
        let angles = AirflowDirection.angles(port.direction); yaw = angles.yaw > 180 ? angles.yaw - 360 : angles.yaw; pitch = angles.pitch
    }
    private func apply() {
        do {
            guard let scenarioIndex = project.scenarios.firstIndex(where: { $0.id == scenario.id }),
                  let deviceIndex = scenario.inputs.hvac.firstIndex(where: { $0.ports.contains { $0.id == portID } }),
                  let portIndex = scenario.inputs.hvac[deviceIndex].ports.firstIndex(where: { $0.id == portID }) else { throw WorkspaceEditingError.noScenario }
            guard yaw.isFinite, pitch.isFinite, (-180...180).contains(yaw), (-90...90).contains(pitch) else { throw PreviewConfigurationEditingError.invalidNumber("送风角度") }
            var candidate = project
            candidate.scenarios[scenarioIndex].inputs.hvac[deviceIndex].ports[portIndex].direction = try AirflowDirection.unit(yawDegrees: yaw, pitchDegrees: pitch)
            try onCommit(candidate); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
