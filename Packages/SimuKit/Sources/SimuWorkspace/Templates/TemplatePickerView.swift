import SwiftUI
import SimuCore
import SimuVisualization

/// The caller commits the complete project and template metadata as one undoable transaction.
@MainActor
public struct TemplatePickerView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var savedDrafts: [String: TemplateOptionsDraft] = [:]
    @State private var kind: ProjectTemplateKind = .office
    @State private var draft = TemplateOptionsDraft(options: .defaults(for: .office))
    @State private var preview: ProjectTemplateInstantiation?
    @State private var previewRequest: PreviewRequest?
    @State private var generationError: String?
    @State private var commitError: String?
    @State private var isGenerating = false
    @State private var confirmDiscard = false
    private let onApply: @MainActor (ProjectDocument, String, Int) throws -> Void

    public init(onApply: @escaping @MainActor (ProjectDocument, String, Int) throws -> Void) {
        self.onApply = onApply
    }

    private var templateDescription: String {
        switch kind {
        case .home: "家庭：起居空间与活动位置；适合观察日常送风方向与家具遮挡。"
        case .office: "办公室：小组工位与桌体；适合观察不同送风方向与遮挡。"
        case .classroom: "教室：成排座位与可选讲台；适合查找密集关注点。"
        }
    }

    public var body: some View {
        NavigationStack {
            EditorForm {
                EditorSection("可编辑布局示例") {
                    Picker("模板", selection: $kind) {
                        ForEach(ProjectTemplateKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }.pickerStyle(.segmented)
                    Text(templateDescription)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("模板带有明确的布局假设，物理输入保持待补充。应用模板将替换项目全部几何与方案。")
                        .font(.footnote).foregroundStyle(.secondary)
                    EditorTextField(title: "项目名称", text: $draft.projectName)
                }
                EditorSection("尺寸与座位") {
                    number("房间宽度 · m", text: $draft.width)
                    number("房间进深 · m", text: $draft.depth)
                    number("房间高度 · m", text: $draft.height)
                    number("座位数量", text: $draft.seatCount)
                    number("最大行数", text: $draft.rows)
                    number("每行列数", text: $draft.columns)
                    number("列间距 · m", text: $draft.columnSpacing)
                    number("排间距 · m", text: $draft.rowSpacing)
                    Text("按列数逐排放置；最后一排可以不满。座位数不得超过行数 × 列数。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                EditorSection("家具与使用条件") {
                    Toggle("创建桌体", isOn: $draft.includeFurniture)
                    number("桌宽 · m", text: $draft.deskWidth).disabled(!draft.includeFurniture)
                    number("桌深 · m", text: $draft.deskDepth).disabled(!draft.includeFurniture)
                    number("桌高 · m", text: $draft.deskHeight).disabled(!draft.includeFurniture)
                    if !draft.includeFurniture { Text("桌体尺寸已保留；重新启用创建桌体时生效。").font(.caption).foregroundStyle(.secondary) }
                    Toggle("创建讲台", isOn: $draft.includeLectern)
                    Toggle("创建人员记录", isOn: $draft.includeOccupants)
                    Toggle("创建桌上热源点", isOn: $draft.includeEquipment)
                    ClockMinuteField(title: "使用开始", text: $draft.activeStartMinute)
                    ClockMinuteField(title: "使用结束", text: $draft.activeEndMinute)
                    Text("其余时段明确停用；热量、活动、衣着和设备性能需要实际依据。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("创建分体空调", isOn: $draft.includeHVAC)
                    Toggle("创建示例门", isOn: $draft.includeDoor)
                    Toggle("创建示例窗", isOn: $draft.includeWindow)
                }
                EditorSection("出处与假设") {
                    Text(kind.descriptor.sourceReference).font(.caption.monospaced())
                    ForEach(kind.descriptor.assumptionNotes, id: \.self) { Text($0).font(.footnote) }
                    Text("覆盖的尺寸和活动时段记录为用户输入；未修改的值记录为内部模板假设。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let commitError {
                    EditorSection("应用失败") { Text(commitError).foregroundStyle(.red) }
                }
            }

            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if isGenerating { ProgressView("正在更新布局…") }
                    if let preview { TemplateLayoutPreview(project: preview.project, columns: Int(draft.columns) ?? 1) }
                    if let generationError { Label(generationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                }.padding(12).background(.regularMaterial)
            }
            .navigationTitle("从模板创建")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if hasDraftChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用模板") { apply() }
                        .disabled(preview == nil || isGenerating || generationError != nil || previewRequest != PreviewRequest(kind: kind, draft: draft))
                }
            }
        }
        .onChange(of: kind) { previous, kind in
            savedDrafts[previous.rawValue] = draft
            draft = savedDrafts[kind.rawValue] ?? TemplateOptionsDraft(options: .defaults(for: kind))
            commitError = nil
        }
        .task(id: PreviewRequest(kind: kind, draft: draft)) { await generatePreview() }
        .interactiveDismissDisabled(hasDraftChanges)
        .confirmationDialog("放弃尚未应用的模板设置？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃设置", role: .destructive) { dismiss() }
        }
        .modifier(EditorSheetSize())
    }

    private var hasDraftChanges: Bool {
        kind != .office || draft != TemplateOptionsDraft(options: .defaults(for: kind))
    }

    private func number(_ label: String, text: Binding<String>) -> some View {
        EditorTextField(title: label, text: text).accessibilityHint("保留未完成输入；只有有效数字才可应用模板。")
    }

    private func generatePreview() async {
        preview = nil
        previewRequest = nil
        generationError = nil
        isGenerating = true
        let selectedKind = kind
        let selectedDraft = draft
        do {
            try await Task.sleep(for: .milliseconds(150))
            let options = try selectedDraft.options()
            let result = try await Task.detached(priority: .userInitiated) {
                try ProjectTemplateFactory.make(kind: selectedKind, options: options)
            }.value
            try Task.checkCancellation()
            preview = result
            previewRequest = PreviewRequest(kind: selectedKind, draft: selectedDraft)
            isGenerating = false
        } catch is CancellationError {
            // A newer draft owns the preview state.
        } catch {
            guard !Task.isCancelled else { return }
            generationError = error.localizedDescription
            isGenerating = false
        }
    }

    private func apply() {
        guard !isGenerating, generationError == nil, let preview,
              previewRequest == PreviewRequest(kind: kind, draft: draft) else { return }
        do {
            // Reparse the live draft so a last keystroke cannot apply a stale valid preview.
            let options = try draft.options()
            guard preview.project.name == options.projectName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            try onApply(preview.project, preview.templateID, preview.templateVersion)
            dismiss()
        } catch { commitError = error.localizedDescription }
    }
}

private struct PreviewRequest: Equatable, Sendable {
    let kind: ProjectTemplateKind
    let draft: TemplateOptionsDraft
}

private struct TemplateOptionsDraft: Equatable, Sendable {
    var projectName: String
    var width: String
    var depth: String
    var height: String
    var seatCount: String
    var rows: String
    var columns: String
    var columnSpacing: String
    var rowSpacing: String
    var deskWidth: String
    var deskDepth: String
    var deskHeight: String
    var activeStartMinute: String
    var activeEndMinute: String
    var includeFurniture: Bool
    var includeOccupants: Bool
    var includeEquipment: Bool
    var includeHVAC: Bool
    var includeDoor: Bool
    var includeWindow: Bool
    var includeLectern: Bool

    init(options: ProjectTemplateOptions) {
        projectName = options.projectName
        width = String(options.width); depth = String(options.depth); height = String(options.height)
        seatCount = String(options.seatCount); rows = String(options.rows); columns = String(options.columns)
        columnSpacing = String(options.columnSpacing); rowSpacing = String(options.rowSpacing)
        deskWidth = String(options.deskWidth); deskDepth = String(options.deskDepth); deskHeight = String(options.deskHeight)
        activeStartMinute = String(options.activeStartMinute); activeEndMinute = String(options.activeEndMinute)
        includeFurniture = options.includeFurniture; includeOccupants = options.includeOccupants
        includeEquipment = options.includeEquipment; includeHVAC = options.includeHVAC
        includeDoor = options.includeDoor; includeWindow = options.includeWindow; includeLectern = options.includeLectern
    }

    func options() throws -> ProjectTemplateOptions {
        func number(_ text: String, _ label: String) throws -> Double {
            guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
                throw ProjectTemplateError.invalidOption("\(label)：请输入有限数字，单位 m。")
            }
            return value
        }
        func integer(_ text: String, _ label: String) throws -> Int {
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ProjectTemplateError.invalidOption("\(label)：请输入整数。")
            }
            return value
        }
        return try .init(projectName: projectName, width: number(width, "房间宽度"), depth: number(depth, "房间进深"),
                         height: number(height, "房间高度"), seatCount: integer(seatCount, "座位数"), rows: integer(rows, "行数"),
                         columns: integer(columns, "列数"), columnSpacing: number(columnSpacing, "列间距"),
                         rowSpacing: number(rowSpacing, "排间距"), deskWidth: number(deskWidth, "桌宽"),
                         deskDepth: number(deskDepth, "桌深"), deskHeight: number(deskHeight, "桌高"),
                         activeStartMinute: integer(activeStartMinute, "使用开始"), activeEndMinute: integer(activeEndMinute, "使用结束"),
                         includeFurniture: includeFurniture, includeOccupants: includeOccupants, includeEquipment: includeEquipment,
                         includeHVAC: includeHVAC, includeDoor: includeDoor, includeWindow: includeWindow, includeLectern: includeLectern)
    }
}

/// A semantic layout preview supplements the plan editor, and remains accessible without a canvas.
private struct TemplateLayoutPreview: View {
    let project: ProjectDocument
    let columns: Int
    var body: some View {
        if let scenario = project.scenarios.first {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(scenario.inputs.usage.seats.count) 个座位 · 每排 \(columns) 列 · \(project.geometry.obstacles.count) 个家具").font(.caption.bold())
                RoomPlanView(project: project, scenarioID: scenario.id, selection: nil,
                    onSelect: { _ in }, onPlace: { _ in }).frame(height: 160).allowsHitTesting(false).accessibilityHidden(true)
                Text("按实际生成尺寸绘制 · 内部布局假设。切换模板会保留各自草稿。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
