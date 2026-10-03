import SwiftUI
import SimuCore

@MainActor
public struct ScenarioListView: View {
    private let project: ProjectDocument
    private let selectedScenarioID: UUID?
    private let baselineScenarioID: UUID?
    private let onSelect: @MainActor (UUID) -> Void
    private let onCommit: @MainActor (ProjectDocument, String) throws -> Void
    private let onSetBaseline: @MainActor (UUID) throws -> Void
    private let onCopy: (@MainActor (ProjectDocument, UUID) throws -> Void)?
    @State private var editName: ScenarioNameRequest?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    public init(project: ProjectDocument, selectedScenarioID: UUID?, baselineScenarioID: UUID?,
                onSelect: @escaping @MainActor (UUID) -> Void,
                onCommit: @escaping @MainActor (ProjectDocument, String) throws -> Void,
                onSetBaseline: @escaping @MainActor (UUID) throws -> Void,
                onCopy: (@MainActor (ProjectDocument, UUID) throws -> Void)? = nil) {
        self.project = project
        self.selectedScenarioID = selectedScenarioID
        self.baselineScenarioID = baselineScenarioID
        self.onSelect = onSelect
        self.onCommit = onCommit
        self.onSetBaseline = onSetBaseline
        self.onCopy = onCopy
    }

    public var body: some View {
        Form {
            Section("方案") {
                if project.scenarios.isEmpty {
                    Text("尚无方案；先创建房间或应用模板。")
                }
                ForEach(project.scenarios, id: \.id) { scenario in
                    Button { onSelect(scenario.id) } label: {
                        HStack {
                            Image(systemName: scenario.id == selectedScenarioID ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scenario.name)
                                Text("\(scenario.inputs.usage.seats.count) 个座位 · \(scenario.inputs.hvac.count) 台空调 · 待计算")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if scenario.id == baselineScenarioID {
                                Label("基准", systemImage: "flag.fill").font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(scenario.name)，\(scenario.id == baselineScenarioID ? "基准方案，" : "")\(scenario.id == selectedScenarioID ? "已选中" : "选择方案")")
                }
            }
            if let scenario = selectedScenario {
                Section("所选方案：\(scenario.name)") {
                    Button("复制为候选", systemImage: "doc.on.doc") {
                        editName = .init(scenarioID: scenario.id, mode: .copy, initialName: candidateName(for: scenario))
                    }
                    Button("重命名", systemImage: "pencil") {
                        editName = .init(scenarioID: scenario.id, mode: .rename, initialName: scenario.name)
                    }
                    if baselineScenarioID != scenario.id {
                        Button("设为基准", systemImage: "flag") {
                            perform { try onSetBaseline(scenario.id) }
                        }
                    } else {
                        Label("当前基准方案", systemImage: "flag.fill")
                    }
                    Button("删除方案", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .disabled(baselineScenarioID == scenario.id)
                    if baselineScenarioID == scenario.id {
                        Text("删除基准前，请先选择另一个方案并设为基准。基准身份随 UUID 保存，不因改名或排序改变。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("编辑与结果状态") {
                Text("各方案保存独立的使用条件、空调与评价输入。房间、门窗和家具几何由整个项目共享。")
                Text("复制候选不会修改基准。编辑快照是输入的独立副本；后续编辑不会改变已捕获快照。输入检查与引擎可用性分别判断。")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section("操作未完成") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editName) { request in
            ScenarioNameSheet(request: request) { name in
                switch request.mode {
                case .copy:
                    let edited = try ScenarioEditing.copy(project, scenarioID: request.scenarioID, name: name)
                    if let onCopy { try onCopy(edited, request.scenarioID) }
                    else { try onCommit(edited, "复制方案") }
                    if let id = edited.scenarios.last?.id { onSelect(id) }
                case .rename:
                    try onCommit(ScenarioEditing.rename(project, scenarioID: request.scenarioID, name: name), "重命名方案")
                }
            }
        }
        .confirmationDialog("删除所选方案及其输入？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除方案", role: .destructive) {
                guard let selectedScenario else { return }
                perform {
                    let result = try ScenarioEditing.delete(project, scenarioID: selectedScenario.id, baselineScenarioID: baselineScenarioID)
                    try onCommit(result.project, "删除方案")
                    if let next = result.project.scenarios.first?.id { onSelect(next) }
                }
            }
        } message: { Text("项目几何不受影响。该操作可通过项目撤销恢复。") }
    }

    private var selectedScenario: Scenario? { project.scenarios.first { $0.id == selectedScenarioID } }

    private func candidateName(for scenario: Scenario) -> String {
        let base = "\(scenario.name) 候选"
        let existing = Set(project.scenarios.map(\.name))
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ScenarioNameRequest: Identifiable {
    enum Mode { case copy, rename }
    let id = UUID()
    let scenarioID: UUID
    let mode: Mode
    let initialName: String
}

@MainActor
private struct ScenarioNameSheet: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    private let request: ScenarioNameRequest
    private let onSave: @MainActor (String) throws -> Void
    @State private var name: String
    @State private var errorMessage: String?
    @State private var confirmDiscard = false

    init(request: ScenarioNameRequest, onSave: @escaping @MainActor (String) throws -> Void) {
        self.request = request
        self.onSave = onSave
        _name = State(initialValue: request.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("方案名称", text: $name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(request.mode == .copy ? "复制为候选" : "重命名方案")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if name != request.initialName { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try onSave(name); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(name != request.initialName)
        .confirmationDialog("放弃尚未保存的名称？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 180)
        #endif
    }
}
