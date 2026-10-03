#if os(macOS)
import RealityKit
import SwiftUI
import SimuCore

/// 3D preview of the room model. Geometry only — no airflow or temperature fields.
/// Dragging a desk, seat, air conditioner, or monitor moves that project item inside the room.
/// RealityView requires macOS 15+ (deployment floor stays macOS 14, ADR-002);
/// older systems get an honest fallback note.
public struct RoomPreview3D: View {
    let layout: RoomPreviewLayout
    let onSelect: (RoomPreviewItem) -> Void
    let onMove: (RoomPreviewItem, Position3D) -> Void

    public init(layout: RoomPreviewLayout,
                onSelect: @escaping (RoomPreviewItem) -> Void = { _ in },
                onMove: @escaping (RoomPreviewItem, Position3D) -> Void = { _, _ in }) {
        self.layout = layout
        self.onSelect = onSelect
        self.onMove = onMove
    }

    public var body: some View {
        if #available(macOS 15.0, *) {
            RoomPreview3DReality(layout: layout, onSelect: onSelect, onMove: onMove)
        } else {
            ContentUnavailableView("3D 预览需要 macOS 15 或更新", systemImage: "cube.transparent",
                                   description: Text("当前系统版本可使用俯视编辑完成全部建模；3D 预览只是只读辅助视图。"))
        }
    }
}

@available(macOS 15.0, *)
private struct RoomPreview3DReality: View {
    let layout: RoomPreviewLayout
    let onSelect: (RoomPreviewItem) -> Void
    let onMove: (RoomPreviewItem, Position3D) -> Void

    @State private var azimuth = -Double.pi / 5
    @State private var elevation = Double.pi / 6
    @State private var distanceFactor = 1.0
    @State private var lastDrag: CGSize = .zero
    @State private var cameraHolder = CameraHolder()
    @State private var shownFingerprint = ""
    @State private var activeDrag: ActiveDrag?

    /// Holds the camera entity across SwiftUI updates so orbit gestures mutate it
    /// without rebuilding the scene.
    final class CameraHolder: @unchecked Sendable {
        weak var camera: PerspectiveCamera?
    }

    struct ActiveDrag {
        var item: RoomPreviewItem
        var domain: Position3D
        var span: RoomPreviewSpan
        var entityStart: SIMD3<Float>
        var grab: SIMD3<Float>?
        var latest: Position3D
    }

    private var suggestedDistance: Double { RoomPreviewLayout.suggestedDistance(roomSize: layout.roomSize) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RealityView { content in
                let camera = PerspectiveCamera()
                camera.name = "camera"
                cameraHolder.camera = camera
                content.add(camera)
                applyCamera()
            } update: { content in
                applyCamera()
                guard activeDrag == nil else { return }
                guard shownFingerprint != layout.fingerprint || !content.entities.contains(where: { $0.name == "room" }) else { return }
                if let existing = content.entities.first(where: { $0.name == "room" }) {
                    content.entities.remove(existing)
                }
                content.add(makeScene())
                shownFingerprint = layout.fingerprint
            }
            .highPriorityGesture(itemGesture)
            .gesture(orbitGesture)
            .gesture(zoomGesture)
            .accessibilityLabel("房间三维预览。拖动桌椅、空调或显示器可在房间内移动；拖空白处旋转。不含气流或温度场")

            HStack {
                Text("拖动物品沿房间地面移动，高度不变 · 拖空白处旋转 · 双指缩放")
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
            guard activeDrag == nil else { return }
            azimuth += Double(value.translation.width - lastDrag.width) * 0.008
            elevation = min(max(elevation - Double(value.translation.height - lastDrag.height) * 0.008, 0.03), 1.45)
            lastDrag = value.translation
        }
        .onEnded { _ in lastDrag = .zero }
    }

    private var itemGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .targetedToAnyEntity()
            .onChanged { value in moveItem(value) }
            .onEnded { _ in finishItemDrag() }
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
        let target = SIMD3<Float>(Float(center.x), Float(center.y), Float(center.z))
        camera.look(at: target, from: position, relativeTo: nil)
    }

    // MARK: - Drag

    private func moveItem(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let holder = dragHolder(value.entity),
              let component = holder.components[PreviewDragComponent.self] else { return }
        if activeDrag == nil {
            activeDrag = ActiveDrag(item: component.item, domain: component.domain, span: component.span,
                                    entityStart: holder.position, grab: nil, latest: component.domain)
            onSelect(component.item)
        }
        guard var drag = activeDrag, drag.item == component.item else { return }
        // Slide on the room's horizontal plane at this item's height, so desks stay on the floor
        // and the movement matches domain X/Y rather than the camera plane.
        guard let current = hitOnItemPlane(value.location, planeY: drag.entityStart.y, value: value) else { return }
        if drag.grab == nil {
            drag.grab = hitOnItemPlane(value.startLocation, planeY: drag.entityStart.y, value: value) ?? current
        }
        var delta = current - (drag.grab ?? current)
        delta.y = 0
        let domain = RoomPreviewDrag.moved(start: drag.domain, appleDelta: delta, roomSize: layout.roomSize, span: drag.span)
        holder.position = drag.entityStart + RoomPreviewDrag.appleShift(from: drag.domain, to: domain)
        drag.latest = domain
        activeDrag = drag
    }

    private func finishItemDrag() {
        if let drag = activeDrag, drag.domain != drag.latest {
            onMove(drag.item, drag.latest)
        }
        activeDrag = nil
        lastDrag = .zero
    }

    private func dragHolder(_ entity: Entity) -> Entity? {
        var node: Entity? = entity
        while let current = node {
            if current.components[PreviewDragComponent.self] != nil { return current }
            node = current.parent
        }
        return nil
    }

    private func hitOnItemPlane(_ point: CGPoint, planeY: Float, value: EntityTargetValue<DragGesture.Value>) -> SIMD3<Float>? {
        guard let ray = value.ray(through: point, in: .local, to: .scene) else { return nil }
        return RoomPreviewDrag.hitHorizontalPlane(origin: ray.origin, direction: ray.direction, planeY: planeY)
    }

    // MARK: - Scene

    private func makeScene() -> Entity {
        let root = Entity()
        root.name = "room"
        let key = DirectionalLight()
        key.light.intensity = 10000
        key.look(at: .zero, from: SIMD3<Float>(1.2, 2.4, 1.6), relativeTo: nil)
        root.addChild(key)
        var groups: [RoomPreviewItem: Entity] = [:]
        func adopt(_ visual: Entity, group: RoomPreviewItem?, anchor: RoomPreviewAnchor?) {
            guard let group else {
                root.addChild(visual)
                return
            }
            let holder: Entity
            if let existing = groups[group] {
                holder = existing
            } else {
                holder = Entity()
                holder.position = visual.position
                holder.components.set(InputTargetComponent())
                if let anchor {
                    holder.components.set(PreviewDragComponent(item: group, domain: anchor.position, span: anchor.span))
                }
                groups[group] = holder
                root.addChild(holder)
            }
            visual.position -= holder.position
            holder.addChild(visual)
        }
        for box in layout.boxes {
            adopt(makeBox(box), group: box.group, anchor: box.anchor)
        }
        for figure in layout.figures {
            adopt(makeFigure(figure), group: figure.group, anchor: figure.anchor)
        }
        for arrow in layout.arrows {
            adopt(makeArrow(arrow), group: arrow.group, anchor: nil)
        }
        for holder in groups.values {
            holder.generateCollisionShapes(recursive: true)
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

@available(macOS 15.0, *)
private struct PreviewDragComponent: Component {
    var item: RoomPreviewItem
    var domain: Position3D
    var span: RoomPreviewSpan
}
#endif
