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
                    Section("几何") {
                        treeRow("房间：\(room.name)", selection: .room(room.id), session: session)
                        ForEach(room.openings, id: \.id) { opening in
                            treeRow("\(opening.kind == .window ? "窗" : "门")", selection: .opening(opening.id), session: session)
                        }
                        ForEach(session.project.geometry.obstacles, id: \.id) { obstacle in
                            treeRow(obstacle.name, selection: .obstacle(obstacle.id), session: session)
                        }
                    }
                }
                if let scenario = session.currentScenario {
                    Section("方案：\(scenario.name)") {
                        ForEach(scenario.inputs.hvac, id: \.id) { device in
                            treeRow(device.name, selection: .device(device.id), session: session)
                        }
                        ForEach(scenario.inputs.usage.seats, id: \.id) { seat in
                            treeRow(seat.name, selection: .seat(seat.id), session: session)
                        }
                        ForEach(scenario.inputs.usage.occupants, id: \.id) { occupant in
                            treeRow("人员", selection: .occupant(occupant.id), session: session)
                        }
                        ForEach(scenario.inputs.usage.equipment, id: \.id) { item in
                            treeRow("设备热源", selection: .equipment(item.id), session: session)
                        }
                        ForEach(scenario.inputs.controls, id: \.id) { control in
                            treeRow("控制", selection: .control(control.id), session: session)
                        }
                        treeRow("环境", selection: .environment, session: session)
                        treeRow("费用", selection: .cost, session: session)
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
                            Label("校验", systemImage: session.validation.passes(.projectIntegrity) ? "checklist" : "exclamationmark.triangle")
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
                ValidationIssueListView(session: session)
                    .navigationTitle("校验")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showValidation = false } } }
            }
            .frame(minWidth: 520, minHeight: 400)
        }
        .confirmationDialog("有未保存的修改", isPresented: $showCloseConfirm) {
            Button("保存并关闭") { save(session) ; store.closeProject() }
            Button("不保存关闭", role: .destructive) { store.closeProject() }
            Button("取消", role: .cancel) {}
        }
    }

    private func treeRow(_ title: String, selection: EntitySelection, session: ProjectSession) -> some View {
        Button {
            session.selection = selection
        } label: {
            HStack {
                Text(title).font(.callout)
                if session.selection == selection {
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(_ session: ProjectSession) -> some View {
        switch store.destination ?? .workspace {
        case .workspace:
            VStack(spacing: 0) {
                TopDownRoomView(session: session)
                HStack {
                    Button("添加座位") { session.selection = session.addSeat() }
                    Button("添加家具") { session.selection = session.addObstacle() }
                    Button("添加空调") { session.selection = session.addDefaultDevice() }
                    Spacer()
                    Text(session.validation.passes(.inputPreparation) ? "输入就绪" : "输入未完成")
                        .font(.caption)
                        .foregroundStyle(session.validation.passes(.inputPreparation) ? .green : .orange)
                }
                .padding(8)
            }
        case .scenarios:
            ScenarioListView(session: session)
        case .runs:
            EmptyStateView("暂无计算任务", symbol: "waveform.path", message: "计算引擎接入后，这里显示任务进度与质量状态。")
        case .reports:
            EmptyStateView("暂无报告", symbol: "doc.text", message: "通过质量检查的结果可用于生成建议报告。")
        }
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
