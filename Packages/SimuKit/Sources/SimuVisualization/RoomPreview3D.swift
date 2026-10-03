#if os(macOS)
import RealityKit
import SwiftUI
import SimuCore

/// Read-only 3D preview of the room model. Geometry only — no airflow or temperature
/// fields; result rendering arrives with P4. Editing stays in the top-down view and
/// the inspector. RealityView requires macOS 15+ (deployment floor stays macOS 14, ADR-002);
/// older systems get an honest fallback note.
public struct RoomPreview3D: View {
    let layout: RoomPreviewLayout

    public init(layout: RoomPreviewLayout) {
        self.layout = layout
    }

    public var body: some View {
        if #available(macOS 15.0, *) {
            RoomPreview3DReality(layout: layout)
        } else {
            ContentUnavailableView("3D 预览需要 macOS 15 或更新", systemImage: "cube.transparent",
                                   description: Text("当前系统版本可使用俯视编辑完成全部建模；3D 预览只是只读辅助视图。"))
        }
    }
}

@available(macOS 15.0, *)
private struct RoomPreview3DReality: View {
    let layout: RoomPreviewLayout

    @State private var azimuth = -Double.pi / 5
    @State private var elevation = Double.pi / 6
    @State private var distanceFactor = 1.0
    @State private var lastDrag: CGSize = .zero
    @State private var cameraHolder = CameraHolder()

    /// Holds the camera entity across SwiftUI updates so orbit gestures mutate it
    /// without rebuilding the scene.
    final class CameraHolder: @unchecked Sendable {
        weak var camera: PerspectiveCamera?
    }

    private var suggestedDistance: Double { RoomPreviewLayout.suggestedDistance(roomSize: layout.roomSize) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RealityView { content in
                let camera = PerspectiveCamera()
                cameraHolder.camera = camera
                content.add(camera)
                content.add(makeScene())
                applyCamera()
            }
            .id(layout.fingerprint)
            .gesture(orbitGesture)
            .gesture(zoomGesture)
            .accessibilityLabel("房间三维示意预览，只读。桌椅、人和空调是外形，不含气流或温度场")

            HStack {
                Text("3D 示意预览（只读）· 拖动旋转 · 双指缩放 · 外形不参与计算，不含气流/温度场")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(6).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
                Button("重置视角") {
                    azimuth = -Double.pi / 5
                    elevation = Double.pi / 6
                    distanceFactor = 1.0
                    applyCamera()
                }
                .font(.caption2)
            }
            .padding(8)
        }
        .onChange(of: azimuth) { applyCamera() }
        .onChange(of: elevation) { applyCamera() }
        .onChange(of: distanceFactor) { applyCamera() }
    }

    // MARK: - Camera

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            azimuth += Double(value.translation.width - lastDrag.width) * 0.008
            elevation = min(max(elevation - Double(value.translation.height - lastDrag.height) * 0.008, 0.03), 1.45)
            lastDrag = value.translation
        }
        .onEnded { _ in lastDrag = .zero }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture().onChanged { value in
            distanceFactor = min(max(1.0 / value.magnification, 0.35), 3.0)
        }
    }

    private func applyCamera() {
        guard let camera = cameraHolder.camera else { return }
        let radius = suggestedDistance * distanceFactor
        let offset = RoomPreviewLayout.cameraOffset(azimuth: azimuth, elevation: elevation, radius: radius)
        let center = layout.roomCenter
        let position = SIMD3<Float>(Float(center.x + offset.x), Float(center.y + offset.y), Float(center.z + offset.z))
        camera.look(at: SIMD3<Float>(Float(center.x), Float(center.y), Float(center.z)), from: position, relativeTo: nil)
    }

    // MARK: - Scene

    private func makeScene() -> Entity {
        let root = Entity()
        let key = DirectionalLight()
        key.light.intensity = 10000
        key.look(at: .zero, from: SIMD3<Float>(1.2, 2.4, 1.6), relativeTo: nil)
        root.addChild(key)
        for box in layout.boxes {
            root.addChild(makeBox(box))
        }
        for figure in layout.figures {
            root.addChild(makeFigure(figure))
        }
        for arrow in layout.arrows {
            root.addChild(makeArrow(arrow))
        }
        return root
    }

    private func makeBox(_ box: RoomPreviewLayout.Box) -> Entity {
        let center = SIMD3<Float>(Float(box.center.x), Float(box.center.y), Float(box.center.z))
        let size = SIMD3<Float>(Float(box.size.x), Float(box.size.y), Float(box.size.z))
        switch box.kind {
        case .obstacle:
            return RoomPreviewMeshes.desk(center: center, size: size)
        case .seat:
            return RoomPreviewMeshes.chair(at: center)
        case .device:
            let facing = SIMD3<Float>(Float(box.facing.x), Float(box.facing.y), Float(box.facing.z))
            return RoomPreviewMeshes.airConditioner(at: center, facing: facing)
        case .window:
            return RoomPreviewMeshes.opening(center: center, size: size, kind: .window)
        case .door:
            return RoomPreviewMeshes.opening(center: center, size: size, kind: .door)
        case .sample:
            return RoomPreviewMeshes.sample(at: center)
        case .floor, .wall:
            let mesh = MeshResource.generateBox(size: size)
            let entity = ModelEntity(mesh: mesh, materials: [material(for: box.kind)])
            entity.position = center
            return entity
        }
    }

    private func makeFigure(_ figure: RoomPreviewLayout.Figure) -> Entity {
        let position = SIMD3<Float>(Float(figure.position.x), Float(figure.position.y), Float(figure.position.z))
        switch figure.kind {
        case .person: return RoomPreviewMeshes.person(at: position)
        case .monitor: return RoomPreviewMeshes.monitor(at: position)
        }
    }

    private func makeArrow(_ arrow: RoomPreviewLayout.Arrow) -> Entity {
        let length = Float(arrow.length)
        let direction = simd_normalize(SIMD3<Float>(Float(arrow.direction.x), Float(arrow.direction.y), Float(arrow.direction.z)))
        let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        let color: NSColor = arrow.role == .supply
            ? .systemOrange.withAlphaComponent(0.95)
            : .systemPurple.withAlphaComponent(0.95)

        let root = Entity()
        let shaftLength = length * 0.7
        let shaft = ModelEntity(mesh: .generateCylinder(height: shaftLength, radius: 0.012),
                                materials: [SimpleMaterial(color: color, isMetallic: false)])
        shaft.orientation = rotation
        shaft.position = direction * (shaftLength / 2)
        let head = ModelEntity(mesh: .generateCone(height: length * 0.3, radius: 0.035),
                               materials: [SimpleMaterial(color: color, isMetallic: false)])
        head.orientation = rotation
        head.position = direction * (shaftLength + length * 0.15)
        root.addChild(shaft)
        root.addChild(head)
        root.position = SIMD3<Float>(Float(arrow.base.x), Float(arrow.base.y), Float(arrow.base.z))
        return root
    }

    private func material(for kind: RoomPreviewLayout.BoxKind) -> any RealityKit.Material {
        switch kind {
        case .floor:
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: NSColor(calibratedRed: 0.82, green: 0.78, blue: 0.72, alpha: 1))
            return material
        case .wall:
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .systemGray.withAlphaComponent(1))
            material.blending = .transparent(opacity: 0.13)
            return material
        case .door, .window, .obstacle, .device, .seat, .sample:
            return SimpleMaterial(color: .systemGray, isMetallic: false)
        }
    }
}
#endif
