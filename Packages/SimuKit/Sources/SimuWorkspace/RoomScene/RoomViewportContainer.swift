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
    @State private var modeBeforePlacement: RoomViewportMode?
    @State private var showLegend = false
    @State private var showGeometry = false
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
                HStack(spacing: 0) {
                    Button("二维") { mode = .plan }.keyboardShortcut("2", modifiers: .command)
                    Button("三维") { if capability.supportsNonAR3D { mode = .threeDimensional } }.keyboardShortcut("3", modifiers: .command)
                }.frame(width: 0, height: 0).clipped().accessibilityHidden(true).disabled(placing)
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
            if let descriptor {
                HStack {
                    Button("表面与门窗") { showGeometry.toggle() }.popover(isPresented: $showGeometry) {
                    ScrollView { VStack(alignment: .leading, spacing: 10) {
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
                    }.padding().frame(width: 300) }.frame(height: 360)
                    }
                    Button("符号图例", systemImage: "info.circle") { showLegend.toggle() }.popover(isPresented: $showLegend) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("家具 · 按尺寸显示的盒体", systemImage: "square.fill")
                            Label("座位 · 人员位置的示意标记", systemImage: "chair.fill")
                            Label("采样点 · 指定的关注位置", systemImage: "smallcircle.filled.circle")
                            Label("热源 · 独立的热量输入点", systemImage: "flame")
                            Label("空调 · 点位符号，无机身几何", systemImage: "air.conditioner.horizontal")
                            Label("风口 · 箭头为输入方向", systemImage: "arrow.up.right")
                            Label("温控测点 · 控制取样位置", systemImage: "thermometer")
                            MethodBoundaryView()
                        }.font(.callout).padding().frame(width: 310)
                    }
                }.controlSize(.small)
            }
        }
        .task(id: RoomSceneBuildInput(project: project,scenarioID: scenarioID)) {
            let input = RoomSceneBuildInput(project: project,scenarioID: scenarioID), registry = registry
            let task = Task.detached(priority: .userInitiated) { RoomSceneBuilder.build(project: input.project,scenarioID: input.scenarioID,registry: registry) }
            let built = await withTaskCancellationHandler(operation: { await task.value },onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            descriptor = built; completedInput = input
        }
        .onChange(of: placing) { _, value in
            if value { modeBeforePlacement = mode; mode = .plan }
            else if let previous = modeBeforePlacement { mode = capability.supportsNonAR3D ? previous : .plan; modeBeforePlacement = nil }
        }
        .onChange(of: capability.supportsNonAR3D) { _, available in if !available { mode = .plan } }
    }
    @ViewBuilder private func geometryObjectActions(_ item: RoomSceneObject) -> some View {
        Button { onSelect(item.key) } label: { Label(item.title,systemImage: selection == item.key ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity,alignment: .leading) }.buttonStyle(.plain)
        if let target = item.target { Button("属性") { onSelect(item.key); onEdit(target) }.disabled(!isCurrent || !canEdit(target)) }
    }
}
