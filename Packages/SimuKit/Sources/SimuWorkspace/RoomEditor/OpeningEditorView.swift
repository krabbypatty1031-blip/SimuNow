import SwiftUI
import SimuCore

public struct OpeningEditorView: View {
    private let project: ProjectDocument
    private let roomID: UUID
    private let openingID: UUID?
    private let registry: ModelRegistry
    private let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var baseProject: ProjectDocument
    @State private var draft: OpeningDraft?
    @State private var baseline: OpeningDraft?
    @State private var error: String?
    @State private var showDiscard = false

    public init(project: ProjectDocument, roomID: UUID, openingID: UUID? = nil,
                registry: ModelRegistry = .builtIn,
                onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void) {
        self.project = project; self.roomID = roomID; self.openingID = openingID
        self.registry = registry; self.onCommit = onCommit
        _baseProject = State(initialValue: project)
        let room = project.geometry.rooms.first { $0.id == roomID }
        let initial: OpeningDraft?
        if let openingID { initial = room?.openings.first { $0.id == openingID }.map(OpeningDraft.init) }
        else { initial = room?.surfaces.first { ![.floor, .ceiling].contains($0.face) }.map { OpeningDraft(surfaceID: $0.id) } }
        _draft = State(initialValue: initial); _baseline = State(initialValue: initial)
    }

    public var body: some View {
        EditorForm {
            if let binding = Binding($draft), let room = project.geometry.rooms.first(where: { $0.id == roomID }) ?? baseProject.geometry.rooms.first(where: { $0.id == roomID }) {
                EditorSection("类型与所属表面") {
                    Picker("类型", selection: binding.kind) {
                        Text("窗").tag(OpeningKind.window)
                        Text("门").tag(OpeningKind.door)
                    }
                    Picker("表面", selection: binding.surfaceID) {
                        ForEach(room.surfaces.filter { ![.floor, .ceiling].contains($0.face) || $0.id == baseline?.surfaceID }, id: \.id) {
                            Text(RoomIssuePresentation.wallTitle($0.face)).tag($0.id)
                        }
                    }
                    if let face = room.surfaces.first(where: { $0.id == binding.wrappedValue.surfaceID })?.face {
                        DisclosureGroup("计算坐标详情") { Text(RoomIssuePresentation.surfaceName(face)).font(.caption) }
                    }
                    Text("偏移从表面的计算坐标最小角开始；U/V 按上方方向递增。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                OpeningElevationView(room: room, draft: binding.wrappedValue, registry: registry)
                EditorSection("位置与尺寸") {
                    PhysicalParameterEditor("U 偏移", draft: binding.offsetU, quantity: LengthTag.self, range: .nonnegative)
                    PhysicalParameterEditor("V 偏移", draft: binding.offsetV, quantity: LengthTag.self, range: .nonnegative)
                    PhysicalParameterEditor("宽度（U）", draft: binding.width, quantity: LengthTag.self, range: .positive)
                    PhysicalParameterEditor("高度（V）", draft: binding.height, quantity: LengthTag.self, range: .positive)
                }
                EditorSection {
                    Text("修改会影响全部方案。新增窗的 U 值、SHGC、遮阳系数及门窗开启比例保持未知。窗改为门时会删除对应窗配置。")
                        .font(.caption).foregroundStyle(.secondary)
                    if isDirty { Label("门窗草稿尚未提交。", systemImage: "pencil.circle").font(.caption) }
                    if hasConflict { Label(conflictMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }

                }
            } else { Text("房间或门窗已经不存在。") }
            if let error { EditorSection("修改未提交") { Text(error).foregroundStyle(.orange).textSelection(.enabled) } }
        }

        .environment(\.editorEntityID, openingID ?? draft?.id)
        .modifier(EditorSheetSize())
        .onChange(of: project) { _, _ in if !isDirty { reload() } }
        .onChange(of: isDirty) { _, dirty in if !dirty && project != baseProject { reload() } }
        .navigationTitle(openingID == nil ? "添加门窗" : "编辑门窗")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { if isDirty { showDiscard = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) { Button(openingID == nil ? "添加门窗" : "应用并关闭") { apply() }.disabled(hasConflict || draft == nil).keyboardShortcut(.defaultAction) }
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog("放弃尚未提交的门窗修改？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
    }
    private var isDirty: Bool { draft != baseline }
    private var hasConflict: Bool { isDirty && project != baseProject }
    private var conflictMessage: String { "项目已变化；当前门窗草稿无法应用。未应用文本仍保留供查看，请关闭后重新打开。" }
    private func apply() {
        guard let draft else { return }
        guard project == baseProject else { error = conflictMessage; return }
        do {
            var candidate = baseProject
            let opening = try draft.opening()
            if openingID == nil { try RoomEditing.addOpening(in: &candidate, roomID: roomID, opening: opening, registry: registry) }
            else { try RoomEditing.updateOpening(in: &candidate, roomID: roomID, opening: opening, registry: registry) }
            try onCommit(candidate, openingID == nil ? "添加门窗及方案引用" : "修改门窗及方案引用")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func reload() {
        let room = project.geometry.rooms.first { $0.id == roomID }
        if let openingID { draft = room?.openings.first { $0.id == openingID }.map(OpeningDraft.init) }
        else { draft = room?.surfaces.first { ![.floor, .ceiling].contains($0.face) }.map { OpeningDraft(surfaceID: $0.id) } }
        baseline = draft; baseProject = project; error = nil
    }
}
