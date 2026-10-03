import SwiftUI
import SimuCore

public struct RoomEditorView: View {
    private let project: ProjectDocument
    private let roomID: UUID
    private let registry: ModelRegistry
    private let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var baseProject: ProjectDocument
    @State private var draft: RoomDraft?
    @State private var baseline: RoomDraft?
    @State private var error: String?
    @State private var openingSheet: OpeningSheetSelection?
    @State private var openingToDelete: UUID?
    @State private var showDiscard = false
    @State private var showCloseDiscard = false

    public init(project: ProjectDocument, roomID: UUID, registry: ModelRegistry = .builtIn,
                onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.roomID = roomID; self.registry = registry; self.onCommit = onCommit
        _baseProject = State(initialValue: project)
        let room = project.geometry.rooms.first { $0.id == roomID }
        let initial = room.flatMap { try? RoomDraft(room: $0, registry: registry) }
        _draft = State(initialValue: initial); _baseline = State(initialValue: initial)
    }

    public var body: some View {
        EditorForm {
            if let room = project.geometry.rooms.first(where: { $0.id == roomID }) ?? baseProject.geometry.rooms.first(where: { $0.id == roomID }), draft != nil {
                roomFields
                EditorSection("门窗（共享几何）") {
                    if room.openings.isEmpty { Text("尚未添加门窗。").foregroundStyle(.secondary) }
                    ForEach(room.openings, id: \.id) { opening in
                        HStack {
                            Button { openingSheet = .init(id: opening.id, isNew: false) } label: {
                                VStack(alignment: .leading) {
                                    Text(opening.kind == .window ? "窗" : "门")
                                    if let face = room.surfaces.first(where: { $0.id == opening.surfaceID })?.face {
                                        Text(RoomIssuePresentation.surfaceName(face)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("\(opening.width.value.map { String($0) } ?? "未知") × \(opening.height.value.map { String($0) } ?? "未知") m")
                                        .font(.caption)
                                }
                            }.buttonStyle(.plain).disabled(isDirty)
                            Spacer()
                            Button(role: .destructive) { openingToDelete = opening.id } label: { Image(systemName: "trash") }
                                .accessibilityLabel("删除\(opening.kind == .window ? "窗" : "门")")
                                .disabled(isDirty)
                        }
                    }
                    Button("添加门窗", systemImage: "plus") { openingSheet = .init(id: UUID(), isNew: true) }
                        .disabled(isDirty)
                    if isDirty { Text("先应用或放弃房间草稿，再编辑门窗。").font(.caption).foregroundStyle(.secondary) }
                    Text("门窗增删及类型转换会同步更新所有方案；窗性能与开启比例仍需按方案补充。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                EditorSection {
                    Label("此房间无法使用矩形编辑器修改。", systemImage: "info.circle")
                    Text("模型数据保留；支持其他房间类型的编辑器将在后续阶段接入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { EditorSection("修改未提交") { Text(error).foregroundStyle(.orange).textSelection(.enabled) } }
        }

        .environment(\.editorEntityID, roomID)
        .onChange(of: project) { _, _ in if !isDirty { reload() } }
        .onChange(of: isDirty) { _, dirty in if !dirty && project != baseProject { reload() } }
        .navigationTitle("编辑房间")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isDirty ? "取消" : "关闭") { if isDirty { showCloseDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("应用修改") { apply() }.disabled(!isDirty || hasConflict).keyboardShortcut(.defaultAction)
            }
        }
        .modifier(EditorSheetSize())
        .interactiveDismissDisabled(isDirty)
        .sheet(item: $openingSheet) { selection in
            NavigationStack {
                OpeningEditorView(project: project, roomID: roomID, openingID: selection.isNew ? nil : selection.id,
                    registry: registry, onCommit: onCommit)
            }.modifier(EditorSheetSize())
        }
        .confirmationDialog("放弃尚未应用的房间修改？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { reload() }
            Button("继续编辑", role: .cancel) {}
        }
        .confirmationDialog("房间草稿尚未应用；放弃修改并关闭？", isPresented: $showCloseDiscard, titleVisibility: .visible) {
            Button("放弃修改并关闭", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .confirmationDialog("删除门窗及其在所有方案中的窗参数和开启状态？", isPresented: Binding(get: { openingToDelete != nil }, set: { if !$0 { openingToDelete = nil } }), titleVisibility: .visible) {
            Button("删除门窗", role: .destructive) { deleteOpening() }
            Button("取消", role: .cancel) { openingToDelete = nil }
        }
    }
    private var isDirty: Bool { draft != baseline }
    private var hasConflict: Bool { isDirty && project != baseProject }
    private var conflictMessage: String { "项目已变化；当前草稿无法应用。未应用文本仍保留供查看，请关闭后重新打开，或明确放弃草稿以加载最新项目。" }
    @ViewBuilder private var roomFields: some View {
        if let draftBinding = Binding($draft) {
            EditorSection("房间尺寸（计算坐标：米，右手 Z-up）") {
                EditorTextField(title: "房间名称", text: draftBinding.name)
                RoomDimensionFields(draft: draftBinding)
            }
            EditorSection("朝向") {
                NorthBearingFields(draft: draftBinding.northAngle)
            }
            EditorSection {
                if isDirty { Label("存在尚未应用的草稿；保存项目不会包含这些文本。", systemImage: "pencil.circle").font(.caption) }
                if hasConflict { Label(conflictMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Button("放弃房间修改", role: .destructive) { showDiscard = true }.disabled(!isDirty)
                Text("修改共享房间会检查全部方案中的门窗、家具、座位和设备；越界修改不会被提交。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func apply() {
        guard let draft else { return }
        guard project == baseProject else { error = conflictMessage; return }
        do {
            var candidate = baseProject
            try RoomEditing.updateRoom(in: &candidate, roomID: roomID, name: draft.name,
                dimensions: draft.dimensions(), northAngle: draft.northAngle.parameter(range: .northBearing), registry: registry)
            try onCommit(candidate, "修改房间尺寸与朝向")
            baseline = draft; baseProject = candidate; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func reload() {
        draft = project.geometry.rooms.first { $0.id == roomID }.flatMap { try? RoomDraft(room: $0, registry: registry) }
        baseline = draft; baseProject = project; error = nil
    }
    private func deleteOpening() {
        guard let openingID = openingToDelete else { return }
        defer { openingToDelete = nil }
        do {
            var candidate = project
            try RoomEditing.deleteOpening(in: &candidate, roomID: roomID, openingID: openingID, registry: registry)
            try onCommit(candidate, "删除门窗及方案引用"); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct OpeningSheetSelection: Identifiable {
    let id: UUID
    let isNew: Bool
}

struct RoomDimensionFields: View {
    @Binding var draft: RoomDraft
    var body: some View {
        PhysicalParameterEditor("宽度（X）", draft: $draft.width, quantity: LengthTag.self, range: .positive)
        PhysicalParameterEditor("进深（Y）", draft: $draft.depth, quantity: LengthTag.self, range: .positive)
        PhysicalParameterEditor("高度（Z）", draft: $draft.height, quantity: LengthTag.self, range: .positive)
        Text("未知尺寸可保存。完整尺寸用于房间显示和位置检查；功率、天气等按各方法另行检查。")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct NorthBearingFields: View {
    @Binding var draft: PhysicalParameterDraft
    var body: some View {
        PhysicalParameterEditor("真北方位角", draft: $draft, quantity: AngleTag.self, range: .northBearing)
        Text("从计算坐标 +Y 顺时针旋转到真北；0° = +Y，90° = +X。视图旋转不改变此参数。")
            .font(.caption).foregroundStyle(.secondary)
        if draft.isKnown, let angle = try? PhysicalParameterDraft.number(draft.valueText), ParameterValueRange.northBearing.contains(angle) {
            HStack {
                Image(systemName: "arrow.up").rotationEffect(.degrees(angle))
                Text("真北：\(angle.formatted())°")
            }.accessibilityElement(children: .combine)
        } else { Text("真北未知；北向未假定为 0°。").font(.caption).foregroundStyle(.secondary) }
    }
}
