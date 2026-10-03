import SwiftUI
import SimuCore
import SimuDesignSystem
import SimuVisualization
#if os(macOS)
import AppKit
#endif

public struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    @State private var showValidation = false
    @State private var showCloseConfirm = false
    @State private var saveError: String?

    public init(store: WorkspaceStore) {
        self._store = State(initialValue: store)
    }

    public var body: some View {
        Group {
            if let session = store.session {
                workspace(session)
            } else {
                HomeView(store: store)
            }
        }
        .modifier(RoomTheme())
        .alert("保存失败", isPresented: .constant(saveError != nil)) {
            Button("好") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    @ViewBuilder
    private func workspace(_ session: ProjectSession) -> some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(WorkspaceDestination.allCases) { destination in
                        Button {
                            store.destination = destination
                        } label: {
                            Label(destination.title, systemImage: destination.symbol)
                                .foregroundStyle(store.destination == destination ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let room = session.project.geometry.rooms.first {
                    Section("我的房间") {
                        treeRow(room.name, detail: "尺寸、朝向和墙面", selection: .room(room.id), session: session)
                        ForEach(room.openings, id: \.id) { opening in
                            treeRow(InputPresentation.openingListTitle(opening, in: room), selection: .opening(opening.id), session: session)
                        }
                        DisclosureGroup("家具 · \(session.project.geometry.obstacles.count)") {
                            ForEach(session.project.geometry.obstacles, id: \.id) { obstacle in
                                treeRow(obstacle.name, selection: .obstacle(obstacle.id), session: session)
                            }
                        }
                    }
                }
                if let scenario = session.currentScenario {
                    Section("方案：\(scenario.name)") {
                        ForEach(scenario.inputs.hvac, id: \.id) { device in
                            treeRow(device.name, selection: .device(device.id), session: session)
                        }
                        DisclosureGroup("座位 · \(scenario.inputs.usage.seats.count)") {
                            ForEach(scenario.inputs.usage.seats, id: \.id) { seat in
                                treeRow(seat.name, selection: .seat(seat.id), session: session)
                            }
                        }
                        DisclosureGroup("人和设备散热") {
                            ForEach(scenario.inputs.usage.occupants, id: \.id) { occupant in
                                let seatName = scenario.inputs.usage.seats.first { $0.id == occupant.seatID }?.name
                                treeRow(seatName.map { "\($0)的人" } ?? "未对应座位的人", selection: .occupant(occupant.id), session: session)
                            }
                            ForEach(Array(scenario.inputs.usage.equipment.enumerated()), id: \.element.id) { index, item in
                                treeRow("设备散热 \(index + 1)", selection: .equipment(item.id), session: session)
                            }
                        }
                        ForEach(scenario.inputs.controls, id: \.id) { control in
                            let deviceName = scenario.inputs.hvac.first { $0.id == control.deviceID }?.name ?? "空调"
                            treeRow("\(deviceName)的设定温度", selection: .control(control.id), session: session)
                        }
                        treeRow("天气与温湿度", selection: .environment, session: session)
                        treeRow("电价与报价", selection: .cost, session: session)
                    }
                }
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            content(session)
                .navigationTitle(store.destination?.title ?? "SimuNow")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { save(session) } label: {
                            Label(session.isDirty ? "保存*" : "保存", systemImage: "square.and.arrow.down")
                        }
                        .help(session.packageURL?.path ?? "尚未保存到文件")
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button { showValidation = true } label: {
                            Label("检查待填信息", systemImage: session.validation.passes(.inputPreparation) ? "checklist" : "exclamationmark.triangle")
                        }
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            if session.isDirty { showCloseConfirm = true } else { store.closeProject() }
                        } label: { Label("关闭项目", systemImage: "xmark.rectangle") }
                    }
                }
        } detail: {
            InspectorView(session: session)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .sheet(isPresented: $showValidation) {
            NavigationStack {
                ValidationIssueListView(session: session) { openSetting($0, session: session); showValidation = false }
                    .navigationTitle("待填信息")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showValidation = false } } }
            }
            .frame(idealWidth: 520, minHeight: 400)
        }
        .confirmationDialog("有未保存的修改", isPresented: $showCloseConfirm) {
            Button("保存并关闭") { save(session) ; store.closeProject() }
            Button("不保存关闭", role: .destructive) { store.closeProject() }
            Button("取消", role: .cancel) {}
        }
    }

    private func treeRow(_ title: String, detail: String? = nil, selection: EntitySelection, session: ProjectSession) -> some View {
        Button {
            session.selection = selection
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout)
                    if let detail {
                        Text(detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if session.selection == selection {
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.map { "\(title)，\($0)" } ?? title)
    }

    @ViewBuilder
    private func content(_ session: ProjectSession) -> some View {
        switch store.destination ?? .workspace {
        case .workspace:
            workspaceEditor(session)
        case .scenarios:
            ComparisonView(session: session, runStore: store.runStore)
        case .runs:
            RunsView(session: session, runStore: store.runStore, onOpenSetting: { openSetting($0, session: session) })
        case .reports:
            ReportView(session: session, runStore: store.runStore)
        }
    }

    private enum WorkspaceViewMode: Hashable { case plan, preview }
    @State private var viewMode: WorkspaceViewMode = .plan

    @ViewBuilder
    private func workspaceEditor(_ session: ProjectSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $viewMode) {
                    Text("俯视编辑").tag(WorkspaceViewMode.plan)
                    Text("3D 预览").tag(WorkspaceViewMode.preview)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, 6)
            Text(viewMode == .plan ? "点选对象修改设置；拖动可调整位置。" : "拖动桌椅、空调或显示器，它们会沿房间地面移动并保持原来的高度。拖空白处旋转。")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 8)
            if viewMode == .plan {
                HStack(spacing: 14) {
                    Label("空调", systemImage: "rectangle.fill").foregroundStyle(.blue)
                    Label("座位", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("家具", systemImage: "rectangle.fill").foregroundStyle(.secondary)
                }
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 6)
            }
            if viewMode == .preview {
                previewPane(session)
            } else {
                TopDownRoomView(session: session)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        editorButtons(session)
                        Spacer()
                        readinessButton(session)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { editorButtons(session) }
                        readinessButton(session)
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func editorButtons(_ session: ProjectSession) -> some View {
        Button("添加座位") { session.selection = session.addSeat() }
        Button("添加家具") { session.selection = session.addObstacle() }
        Button("添加空调") { session.selection = session.addDefaultDevice() }
    }

    private func readinessButton(_ session: ProjectSession) -> some View {
        Button { showValidation = true } label: {
            Label(session.validation.passes(.inputPreparation) ? "可以估算" : "还有信息待填",
                  systemImage: session.validation.passes(.inputPreparation) ? "checkmark.circle" : "exclamationmark.circle")
        }
        .buttonStyle(.borderless).font(.caption)
    }

    /// Read-only 3D geometry preview (RealityView on macOS 14+; iOS 17 shows the fallback note).
    @ViewBuilder
    private func previewPane(_ session: ProjectSession) -> some View {
        #if os(macOS)
        if let room = session.project.geometry.rooms.first,
           let layout = RoomPreviewLayout.build(room: room,
                                                obstacles: session.project.geometry.obstacles,
                                                seats: session.currentScenario?.inputs.usage.seats ?? [],
                                                devices: session.currentScenario?.inputs.hvac ?? [],
                                                registry: session.registry,
                                                occupants: session.currentScenario?.inputs.usage.occupants ?? [],
                                                equipment: session.currentScenario?.inputs.usage.equipment ?? []) {
            RoomPreview3D(layout: layout, onSelect: { item in
                session.selection = RoomMotion.selection(for: item)
            }, onMove: { item, position in
                RoomMotion.apply(item, to: position, session: session)
            })
        } else {
            ContentUnavailableView("先填写房间尺寸", systemImage: "cube.transparent",
                                   description: Text("尺寸齐全后，可以查看房间外观。"))
        }
        #else
        ContentUnavailableView("请在 Mac 上查看 3D", systemImage: "cube.transparent",
                               description: Text("手机和平板上可以使用俯视图布置房间。"))
        #endif
    }

    private func openSetting(_ target: SettingTarget, session: ProjectSession) {
        if let scenarioID = target.scenarioID {
            session.currentScenarioID = scenarioID
        }
        store.destination = .workspace
        session.selection = target.selection
        session.focusedSetting = target.anchor
    }

    private func save(_ session: ProjectSession) {
        do {
            if session.packageURL != nil {
                try session.save()
            } else {
                try saveAs(session)
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveAs(_ session: ProjectSession) throws {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.project.name).simunow"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try session.save(to: url)
        #else
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try session.save(to: documents.appendingPathComponent("\(session.project.name).simunow"))
        #endif
    }
}
