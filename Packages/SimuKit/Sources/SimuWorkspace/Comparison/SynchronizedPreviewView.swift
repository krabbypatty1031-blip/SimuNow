import SwiftUI
import SimuCore
import SimuVisualization

@MainActor public struct SynchronizedPreviewView: View {
    let project: ProjectDocument
    let artifacts: [NativeAnalysisArtifact]
    @State private var descriptors: [UUID: SceneDescriptor] = [:]
    @State private var camera: RoomCameraState?
    @State private var frozenProjects: [UUID: ProjectDocument] = [:]
    public init(project: ProjectDocument, artifacts: [NativeAnalysisArtifact]) { self.project = project; self.artifacts = artifacts }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("同视角查看固定证据").font(.subheadline)
            Text("每幅图使用各自固定输入；相机值同步，选取与 Entity 保持独立。拖动任一视图会同步视角；旧系统提供二维图与逐点文字比较。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(artifacts, id: \.manifest.runID) { artifact in
                let id = artifact.manifest.runID
                if let descriptor = descriptors[id] {
                    Text(project.scenarios.first { $0.id == artifact.manifest.scenarioID }?.name ?? "历史方案").font(.caption)
                    if RendererCapabilities.current.supportsNonAR3D {
                        RealityKitRoomViewport(descriptor: descriptor, selection: nil,
                            overlay: (try? AirflowOverlayDescriptor(result: artifact.result).scene) ?? .empty,
                            inputEnabled: true, cameraOverride: camera, onCameraChange: { camera = $0 }, onSelect: { _ in })
                    } else if let frozen = frozenProjects[id] {
                        RoomPlanView(project: frozen, scenarioID: artifact.manifest.scenarioID, selection: nil,
                            overlay: (try? AirflowOverlayDescriptor(result: artifact.result).scene) ?? .empty,
                            onSelect: { _ in }, onPlace: { _ in })
                    }
                }
            }
        }.task(id: artifacts.map(\.manifest.runID)) {
            let evidence = artifacts, spaceType = project.spaceType
            let worker = Task.detached {
                let values = evidence.map { artifact in
                    let s = artifact.request.resolvedInput.snapshot
                    let value = ProjectDocument(id: s.projectID, name: "固定证据", spaceType: spaceType,
                        geometry: s.geometry, scenarios: [.init(id: s.scenarioID, name: "固定方案", inputs: s.inputs, evaluation: s.evaluation)])
                    return (artifact.manifest.runID, value, RoomSceneBuilder.build(project: value, scenarioID: s.scenarioID))
                }
                return (Dictionary(uniqueKeysWithValues: values.map { ($0.0, $0.2) }),
                        Dictionary(uniqueKeysWithValues: values.map { ($0.0, $0.1) }))
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            descriptors = result.0; frozenProjects = result.1
            if let bounds = result.0.values.first?.bounds { camera = .fitting(bounds: bounds, aspectRatio: 1) }
        }
    }
}
