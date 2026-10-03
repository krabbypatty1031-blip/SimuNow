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
            .accessibilityLabel("房间三维几何预览，只读，不含气流或温度场")

            HStack {
                Text("3D 几何预览（只读）· 拖动旋转 · 双指缩放 · 不含气流/温度场")
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
        for box in layout.boxes {
            root.addChild(makeBox(box))
        }
        for arrow in layout.arrows {
            root.addChild(makeArrow(arrow))
        }
        return root
    }

    private func makeBox(_ box: RoomPreviewLayout.Box) -> Entity {
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(Float(box.size.x), Float(box.size.y), Float(box.size.z)))
        let entity = ModelEntity(mesh: mesh, materials: [material(for: box.kind)])
        entity.position = SIMD3<Float>(Float(box.center.x), Float(box.center.y), Float(box.center.z))
        return entity
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
            material.baseColor = .init(tint: .lightGray.withAlphaComponent(0.9))
            return material
        case .wall:
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .systemGray.withAlphaComponent(1))
            material.blending = .transparent(opacity: 0.13)
            return material
        case .door:
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .systemBrown.withAlphaComponent(1))
            material.blending = .transparent(opacity: 0.6)
            return material
        case .window:
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .systemCyan.withAlphaComponent(1))
            material.blending = .transparent(opacity: 0.45)
            return material
        case .obstacle:
            return SimpleMaterial(color: .systemGray.withAlphaComponent(0.85), isMetallic: false)
        case .device:
            return SimpleMaterial(color: .systemBlue.withAlphaComponent(0.9), isMetallic: false)
        case .seat:
            return SimpleMaterial(color: .systemGreen.withAlphaComponent(0.95), isMetallic: false)
        case .sample:
            return SimpleMaterial(color: .systemTeal.withAlphaComponent(0.9), isMetallic: false)
        }
    }
}
#endif
