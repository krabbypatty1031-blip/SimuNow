import SwiftUI
import SimuCore
import SimuVisualization

public enum RoomViewportMode: String, Sendable { case threeDimensional, plan }

/// Shared renderer selection, with the complete P2 plan fallback and unchanged edit transactions.
@MainActor
public struct RoomViewportContainer: View {
    private let project: ProjectDocument
    private let scenarioID: UUID
    private let registry: ModelRegistry
    private let capability: RendererCapabilities
    private let selection: SceneObjectKey?
    private let planSelection: RoomPlanSelection?
    private let placing: Bool
    private let overlay: RoomSceneOverlay
    private let onSelect: @MainActor (SceneObjectKey?) -> Void
    private let onPlace: @MainActor (Position3D) -> Void
    private let onEdit: @MainActor (RoomSceneSelectionTarget) -> Void
    private let canEdit: @MainActor (RoomSceneSelectionTarget) -> Bool
    @State private var mode: RoomViewportMode
    @State private var descriptor: SceneDescriptor?
    @State private var completedInput: RoomSceneBuildInput?
    private var isCurrent: Bool { completedInput?.permitsSelection(currentProject: project, scenarioID: scenarioID) == true }
    public init(project: ProjectDocument, scenarioID: UUID, registry: ModelRegistry = .builtIn,
                capability: RendererCapabilities = .current, selection: SceneObjectKey?, planSelection: RoomPlanSelection?,
                placing: Bool = false, overlay: RoomSceneOverlay = .empty,
                onSelect: @escaping @MainActor (SceneObjectKey?) -> Void, onPlace: @escaping @MainActor (Position3D) -> Void,
                canEdit: @escaping @MainActor (RoomSceneSelectionTarget) -> Bool,
                onEdit: @escaping @MainActor (RoomSceneSelectionTarget) -> Void) {
        self.project = project; self.scenarioID = scenarioID; self.registry = registry; self.capability = capability
        self.selection = selection; self.planSelection = planSelection; self.placing = placing; self.overlay = overlay
        self.onSelect = onSelect; self.onPlace = onPlace; self.canEdit = canEdit; self.onEdit = onEdit
        _mode = State(initialValue: capability.supportsNonAR3D ? .threeDimensional : .plan)
    }
    public var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            if capability.supportsNonAR3D {
                Picker("房间查看方式",selection: $mode) {
                    Text("三维查看").tag(RoomViewportMode.threeDimensional)
                    Text("二维编辑").tag(RoomViewportMode.plan)
                }.pickerStyle(.segmented).disabled(placing)
            } else { Text(capability.explanation).font(.caption).foregroundStyle(.secondary) }
            if mode == .threeDimensional && capability.supportsNonAR3D && !placing {
                if let descriptor, descriptor.projectID == project.id {
                    if !isCurrent { Text("正在更新房间；所示为上一份几何，选择暂不可用。") .font(.caption).foregroundStyle(.secondary) }
                    if descriptor.bounds != nil {
                        RealityKitRoomViewport(descriptor: descriptor,selection: selection,overlay: isCurrent ? overlay : .empty, inputEnabled: isCurrent, onSelect: { if isCurrent { onSelect($0) } })
                    } else { ContentUnavailableView("没有可显示的三维几何",systemImage: "cube",description: Text("请检查下方问题和对象；二维与属性表单仍可使用。")) }
                } else { ProgressView("正在准备房间几何…").frame(minHeight: 260) }
            } else {
                RoomPlanView(project: project,scenarioID: scenarioID,selection: planSelection,registry: registry,placing: placing,overlay: overlay,
                             onSelect: { onSelect(.init($0)) },onPlace: onPlace)
            }
            if let selected = descriptor?.object(selection) {
                Label("已选：" + selected.title,systemImage: "checkmark.circle.fill")
                Text(selected.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
                if let target = selected.target {
                    Button("编辑所选属性") { onEdit(target) }.disabled(!isCurrent || !canEdit(target))
                }
            }
            if let descriptor {
                DisclosureGroup("房间表面与门窗 · \(descriptor.objects.filter { [.room,.surface,.opening].contains($0.key.category) }.count) 项") {
                    ForEach(descriptor.objects.filter { [.room,.surface,.opening].contains($0.key.category) }) { item in
                        ViewThatFits(in: .horizontal) {
                            HStack { geometryObjectActions(item) }.disabled(!isCurrent)
                            VStack(alignment: .leading) { geometryObjectActions(item) }.disabled(!isCurrent)
                        }
                    }
                }
                if !descriptor.issues.isEmpty {
                    DisclosureGroup("未显示或需检查：\(descriptor.issues.count) 项") {
                        ForEach(descriptor.issues) { issue in
                            VStack(alignment: .leading,spacing: 4) {
                                Label(issue.message,systemImage: "exclamationmark.triangle").font(.caption)
                                if let key = issue.key, let item = descriptor.object(key) {
                                    Button("定位：" + item.title) { if isCurrent { onSelect(key) } }.disabled(!isCurrent)
                                }
                            }.padding(.vertical,2)
                        }
                    }
                }
            }
            Text("家具按模型尺寸显示；空调、人员、座位和点位使用示意符号。三维显示不代表气流或热量结果。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
        }
        .task(id: RoomSceneBuildInput(project: project,scenarioID: scenarioID)) {
            let input = RoomSceneBuildInput(project: project,scenarioID: scenarioID), registry = registry
            let task = Task.detached(priority: .userInitiated) { RoomSceneBuilder.build(project: input.project,scenarioID: input.scenarioID,registry: registry) }
            let built = await withTaskCancellationHandler(operation: { await task.value },onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            descriptor = built; completedInput = input
        }
        .onChange(of: placing) { _, value in if value { mode = .plan } }
        .onChange(of: capability.supportsNonAR3D) { _, available in if !available { mode = .plan } }
    }
    @ViewBuilder private func geometryObjectActions(_ item: RoomSceneObject) -> some View {
        Button { onSelect(item.key) } label: { Label(item.title,systemImage: selection == item.key ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity,alignment: .leading) }.buttonStyle(.plain)
        if let target = item.target { Button("属性") { onSelect(item.key); onEdit(target) }.disabled(!isCurrent || !canEdit(target)) }
    }
}
