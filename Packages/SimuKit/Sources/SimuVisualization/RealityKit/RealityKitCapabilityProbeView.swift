import SwiftUI
import RealityKit

/// Development-only non-AR capability probe. Production room rendering is N2.
@MainActor
public struct RealityKitCapabilityProbeView: View {
    public init() {}
    public var body: some View {
        if #available(macOS 15, iOS 18, *) { NativeRealityKitProbe() }
        else { Text(RendererCapabilities.current.explanation).padding() }
    }
}

@available(macOS 15, iOS 18, *)
@MainActor
private struct NativeRealityKitProbe: View {
    @State private var yaw: Float = 0.7
    @State private var distance: Float = 6
    @State private var selected = false
    @State private var controlMode = 0
    @State private var canvasTaps = 0
    @State private var boxHits = 0
    @State private var lastInput = "尚未点击画布"

    private var nativeControls: Bool { controlMode != 0 }

    var body: some View {
        VStack {
            Text("N1 非 AR 三维能力验证").font(.title2)
            Text("米制盒体；无需摄像。绿色表示选中。相机控制仅选一种。")
            NativeProbeCanvas(yaw: yaw, distance: distance, selected: selected, controlMode: controlMode) { hit in
                canvasTaps += 1
                switch hit {
                case .unavailable:
                    lastInput = "场景尚未就绪"
                case .entity(let entity):
                    if entity?.name == "probe-box" {
                        boxHits += 1
                        selected.toggle()
                        lastInput = "射线命中 probe-box"
                    } else {
                        lastInput = "射线未命中盒体"
                    }
                }
            }
            // Switching camera ownership starts a fresh scene. Disabling a custom
            // camera does not establish that RealityView restored its default camera.
            .id(controlMode)
            .frame(minHeight: 300)
            HStack {
                Button("向左旋转") { yaw -= 0.3 }.disabled(nativeControls)
                Button("向右旋转") { yaw += 0.3 }.disabled(nativeControls)
                Button("放大") { distance = max(2, distance - 0.5) }.disabled(nativeControls)
                Button("缩小") { distance = min(12, distance + 0.5) }.disabled(nativeControls)
                Button("重置") {
                    yaw = 0.7; distance = 6; selected = false; controlMode = 0
                    canvasTaps = 0; boxHits = 0; lastInput = "尚未点击画布"
                }
            }.buttonStyle(.bordered)
            Picker("相机模式", selection: $controlMode) {
                Text("自管相机").tag(0)
                Text("系统 orbit").tag(1)
                Text("系统 dolly").tag(2)
            }.pickerStyle(.segmented)
            Text("画布点击 \(canvasTaps) 次 · 盒体命中 \(boxHits) 次 · \(lastInput)")
                .font(.caption)
                .accessibilityIdentifier("native-probe-hit-status")
            Text(selected ? "已选中 1 m 盒体" : "点选盒体，或使用此无手势入口")
            Button(selected ? "取消选择盒体" : "选择盒体") {
                selected.toggle()
                lastInput = "通过按钮更改选择"
            }.buttonStyle(.bordered)
        }.padding()
    }
}

@available(macOS 15, iOS 18, *)
@MainActor
private struct NativeProbeCanvas: View {
    let yaw: Float
    let distance: Float
    let selected: Bool
    let controlMode: Int
    let onTap: (ProbeHit) -> Void
    @State private var hitContext = ProbeHitContext()

    private static let coordinateSpaceName = "simunow-native-probe-canvas"

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            root.name = "probe-root"
            let cube = ModelEntity(mesh: .generateBox(size: 1), materials: [material(selected ? .green : .blue)])
            cube.name = "probe-box"
            cube.position = [0, 0.5, 0]
            cube.components.set(InputTargetComponent())
            cube.generateCollisionShapes(recursive: false)
            root.addChild(cube)

            let floor = ModelEntity(mesh: .generateBox(size: [4, 0.02, 4]), materials: [material(.gray)])
            floor.position.y = -0.01
            root.addChild(floor)
            // Asymmetric static markers make an actual camera orbit observable.
            let xMarker = ModelEntity(mesh: .generateBox(size: [0.4, 0.2, 0.2]), materials: [material(.red)])
            xMarker.position = [1.4, 0.1, 0.2]
            root.addChild(xMarker)
            let zMarker = ModelEntity(mesh: .generateBox(size: [0.2, 0.3, 0.3]), materials: [material(.yellow)])
            zMarker.position = [0, 0.15, -1.2]
            root.addChild(zMarker)

            if controlMode == 0 {
                let camera = Entity()
                camera.name = "probe-camera"
                camera.components.set(PerspectiveCameraComponent(near: 0.01, far: 100, fieldOfViewInDegrees: 45))
                root.addChild(camera)
                position(camera)
            }
            content.add(root)
            if controlMode != 0 { content.cameraTarget = root }
            hitContext.content = content
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "probe-root" }) else { return }
            if let cube = root.findEntity(named: "probe-box") as? ModelEntity {
                cube.model?.materials = [material(selected ? .green : .blue)]
            }
            if let camera = root.findEntity(named: "probe-camera") { position(camera) }
            // Store the latest content projection context without publishing SwiftUI
            // state from this update closure or adding a per-frame subscription.
            hitContext.content = content
        }
        .realityViewCameraControls(controlMode == 1 ? .orbit : controlMode == 2 ? .dolly : .none)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.coordinateSpaceName)
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpaceName))
                .onEnded { event in
                    guard let content = hitContext.content else { onTap(.unavailable); return }
                    // This is a real collision-shape raycast from the pointer/touch
                    // position, not a screen rectangle or a selection-button proxy.
                    onTap(.entity(content.entity(at: event.location, in: .named(Self.coordinateSpaceName))))
                }
        )
        .onDisappear { hitContext.content = nil }
    }

    private func position(_ camera: Entity) {
        let location = SIMD3<Float>(distance * sin(yaw), distance * 0.55, distance * cos(yaw))
        camera.look(at: [0, 0.5, 0], from: location, relativeTo: nil)
    }

    private func material(_ color: Color) -> SimpleMaterial {
        SimpleMaterial(color: .init(color), isMetallic: false)
    }
}

@available(macOS 15, iOS 18, *)
@MainActor
private final class ProbeHitContext {
    var content: RealityViewCameraContent?
}

@available(macOS 15, iOS 18, *)
private enum ProbeHit {
    case unavailable
    case entity(Entity?)
}
