import SwiftUI
import SimuCore

public struct RoomWizardView: View {
    private let registry: ModelRegistry
    private let onCreate: @MainActor (ProjectDocument) throws -> Void
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var projectID = UUID()
    @State private var scenarioID = UUID()
    @State private var name = "未命名项目"
    @State private var spaceType = SpaceType.office
    @State private var draft = RoomDraft()
    @State private var openings: [Opening] = []
    @State private var step = 0
    @State private var error: String?
    @State private var openingSheet: WizardOpeningSelection?
    @State private var openingToDelete: UUID?
    @State private var showDiscard = false

    public init(registry: ModelRegistry = .builtIn,
                onCreate: @escaping @MainActor (ProjectDocument) throws -> Void) {
        self.registry = registry; self.onCreate = onCreate
    }

    public var body: some View {
        Form {
            Section {
                Text("第 \(step + 1) / 4 步：\(titles[step])").font(.headline)
                ProgressView(value: Double(step + 1), total: 4).accessibilityLabel("建模进度")
            }
            switch step {
            case 0:
                Section("项目") {
                    TextField("项目名称", text: $name)
                    Picker("空间用途", selection: $spaceType) {
                        Text("办公室").tag(SpaceType.office)
                        Text("教室").tag(SpaceType.classroom)
                    }
                    TextField("房间名称", text: $draft.name)
                }
            case 1:
                Section("房间尺寸") { RoomDimensionFields(draft: $draft) }
                Section("朝向") { NorthBearingFields(draft: $draft.northAngle) }
            case 2:
                Section("门窗") {
                    if openings.isEmpty { Text("尚未添加门窗；可以在创建后继续补充。").foregroundStyle(.secondary) }
                    ForEach(openings, id: \.id) { opening in
                        HStack {
                            Button(opening.kind == .window ? "编辑窗" : "编辑门") {
                                openingSheet = .init(id: opening.id, isNew: false)
                            }
                            Spacer()
                            Text("\(opening.width.value.map { String($0) } ?? "未知") × \(opening.height.value.map { String($0) } ?? "未知") m")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(role: .destructive) { openingToDelete = opening.id } label: { Image(systemName: "trash") }
                                .accessibilityLabel("删除门窗")
                        }
                    }
                    Button("添加门窗", systemImage: "plus") { openingSheet = .init(id: UUID(), isNew: true) }
                }
            default:
                Section("创建摘要") {
                    LabeledContent("项目", value: name)
                    LabeledContent("房间", value: draft.name)
                    LabeledContent("用途", value: spaceType == .office ? "办公室" : "教室")
                    LabeledContent("门窗", value: "\(openings.count) 个")
                    Text("将创建一个基准方案。几何和物理参数可以明确标记未知；输入不完整时不能计算。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("围护暴露和边界模式尚未配置；请在使用条件中按实际情况设置。窗参数、通风与环境参数保持未知。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("未知、假设与预设") {
                    if let project = try? buildProject() { ParameterAssumptionsView(project: project, registry: registry) }
                }
            }
            if let error { Section("请修正后继续") { Text(error).foregroundStyle(.orange).textSelection(.enabled) } }
            Section {
                HStack {
                    if step > 0 { Button("上一步") { step -= 1; error = nil } }
                    Spacer()
                    Button(step == 3 ? "创建项目" : "下一步") { advance() }
                }
            }
        }
        .navigationTitle("创建矩形房间")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showDiscard = true } } }
        .interactiveDismissDisabled()
        .confirmationDialog("放弃此向导中的草稿？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃创建", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .confirmationDialog("删除此门窗？", isPresented: Binding(get: { openingToDelete != nil }, set: { if !$0 { openingToDelete = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { openings.removeAll { $0.id == openingToDelete }; openingToDelete = nil }
            Button("取消", role: .cancel) { openingToDelete = nil }
        }
        .sheet(item: $openingSheet) { selection in
            if let project = try? buildProject() {
                NavigationStack {
                    OpeningEditorView(project: project, roomID: draft.id,
                        openingID: selection.isNew ? nil : selection.id, registry: registry) { candidate, _ in
                        openings = candidate.geometry.rooms.first { $0.id == draft.id }?.openings ?? []
                    }
                }
            } else { Text("请先完成房间字段并修正输入错误。") }
        }
    }
    private var titles: [String] { ["项目与用途", "尺寸与朝向", "门窗", "输入摘要"] }
    private func buildProject() throws -> ProjectDocument {
        try RoomEditing.createProject(name: name, spaceType: spaceType, room: draft.room(openings: openings),
            projectID: projectID, scenarioID: scenarioID, registry: registry)
    }
    private func advance() {
        do {
            if step == 0 {
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RoomEditingError.nameRequired }
            } else { _ = try buildProject() }
            if step == 3 { try onCreate(buildProject()); dismiss() }
            else { step += 1 }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct WizardOpeningSelection: Identifiable {
    let id: UUID
    let isNew: Bool
}
