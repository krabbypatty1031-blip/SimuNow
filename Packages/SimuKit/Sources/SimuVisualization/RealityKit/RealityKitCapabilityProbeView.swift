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
    private var nativeControls: Bool { controlMode != 0 }
    var body: some View {
        VStack {
            Text("N1 非 AR 三维能力验证").font(.title2)
            Text("米制盒体；无需摄像。绿色表示选中。相机控制仅选一种。")
            RealityView { content in
                content.camera = .virtual
                let root = Entity(); root.name = "probe-root"
                let cube = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial(color: .blue, isMetallic: false)])
                cube.name = "probe-box"; cube.position = [0,0.5,0]
                cube.components.set(InputTargetComponent()); cube.generateCollisionShapes(recursive: false); root.addChild(cube)
                let floor = ModelEntity(mesh: .generateBox(size: [4,0.02,4]), materials: [SimpleMaterial(color: .gray, isMetallic: false)])
                floor.position.y = -0.01; root.addChild(floor)
                let camera = Entity(); camera.name = "probe-camera"
                camera.components.set(PerspectiveCameraComponent(near: 0.01, far: 100, fieldOfViewInDegrees: 45)); root.addChild(camera)
                content.add(root)
                if !nativeControls { position(camera) }
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == "probe-root" }) else { return }
                if let cube = root.findEntity(named: "probe-box") as? ModelEntity {
                    cube.model?.materials = [SimpleMaterial(color: selected ? .green : .blue, isMetallic: false)]
                }
                if let camera = root.findEntity(named: "probe-camera") { camera.isEnabled = !nativeControls; if !nativeControls { position(camera) } }
            }
            .realityViewCameraControls(controlMode == 1 ? .orbit : controlMode == 2 ? .dolly : .none)
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { event in if event.entity.name == "probe-box" { selected.toggle() } })
            .frame(minHeight: 300)
            HStack {
                Button("向左旋转") { yaw -= 0.3 }.disabled(nativeControls)
                Button("向右旋转") { yaw += 0.3 }.disabled(nativeControls)
                Button("放大") { distance = max(2,distance-0.5) }.disabled(nativeControls)
                Button("缩小") { distance = min(12,distance+0.5) }.disabled(nativeControls)
                Button("重置") { yaw = 0.7; distance = 6; selected = false; controlMode = 0 }
            }.buttonStyle(.bordered)
            Picker("相机模式", selection: $controlMode) {
                Text("自管相机").tag(0); Text("系统 orbit").tag(1); Text("系统 dolly").tag(2)
            }.pickerStyle(.segmented)
            Text(selected ? "已选中 1 m 盒体" : "点选盒体，或使用此无手势入口")
            Button(selected ? "取消选择盒体" : "选择盒体") { selected.toggle() }.buttonStyle(.bordered)
        }.padding()
    }
    private func position(_ camera: Entity) {
        let location = SIMD3<Float>(distance*sin(yaw), distance*0.55, distance*cos(yaw))
        camera.look(at: [0,0.5,0], from: location, relativeTo: nil)
    }
}
