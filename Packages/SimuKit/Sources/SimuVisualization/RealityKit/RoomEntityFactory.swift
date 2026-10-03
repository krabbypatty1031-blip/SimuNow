import Foundation
import RealityKit
import SimuCore
import simd

@available(macOS 15, iOS 18, *)
@MainActor
final class RoomEntityFactory {
    private var box: MeshResource?
    private var sphere: MeshResource?
    private var cylinder: MeshResource?
    private var cone: MeshResource?
    let palette = RoomMaterialPalette()
    var meshCount: Int { [box,sphere,cylinder,cone].compactMap { $0 }.count }
    func entity(_ node: RoomSceneNode, dark: Bool, selected: Bool) -> Entity {
        let root = Entity(); root.name = node.key.id
        updateGeometry(root, node: node, dark: dark, selected: selected)
        return root
    }
    func updateGeometry(_ root: Entity, node: RoomSceneNode, dark: Bool, selected: Bool) {
        for child in Array(root.children) { child.removeFromParent() }
        let material = palette.material(node.material,dark: dark,selected: selected)
        switch node.geometry {
        case .box(let size):
            let model = ModelEntity(mesh: boxMesh(),materials: [material]); model.scale = vector(CoordinateTransform.appleDimensions(size)); root.addChild(model)
        case .sphere(let radius):
            let model = ModelEntity(mesh: sphereMesh(),materials: [material]); model.scale = .init(repeating: Float(radius)); root.addChild(model)
        case .segment(let direction, let radius):
            addSegment(to: root, vector: .init(x: direction.x,y: direction.y,z: direction.z), radius: radius, material: material)
        case .arrow(let direction, let length, let radius):
            let apple = vector(CoordinateTransform.toApple(direction)), unit = simd_normalize(apple)
            let bodyLength = Float(length)*0.76, headLength = Float(length)*0.24
            let body = ModelEntity(mesh: cylinderMesh(),materials: [material]); body.scale = [Float(radius),bodyLength,Float(radius)]
            body.position = unit*bodyLength/2; body.orientation = simd_quatf(from: [0,1,0],to: unit); root.addChild(body)
            let head = ModelEntity(mesh: coneMesh(),materials: [material]); head.scale = [Float(radius)*3,headLength,Float(radius)*3]
            head.position = unit*(bodyLength+headLength/2); head.orientation = body.orientation; root.addChild(head)
        }
        root.position = vector(CoordinateTransform.toApple(node.position))
        updateInput(root,selectable: node.selectable)
    }
    func updateInput(_ root: Entity, selectable: Bool) {
        for child in root.children {
            if selectable { child.components.set(InputTargetComponent()); child.generateCollisionShapes(recursive: false) }
            else { child.components.remove(InputTargetComponent.self); child.components.remove(CollisionComponent.self) }
        }
    }
    func updateMaterial(_ root: Entity, role: RoomSceneMaterial, dark: Bool, selected: Bool) {
        let material = palette.material(role,dark: dark,selected: selected)
        for child in root.children { if let model = child as? ModelEntity { model.model?.materials = [material] } }
    }
    func overlayPath(_ path: RoomOverlayPath, dark: Bool) -> Entity {
        let root = Entity(); root.name = "overlay/" + path.id
        let material = palette.material(path.blocked ? .blocked : .preview,dark: dark)
        for (i,p) in path.points.dropLast().enumerated() {
            let next = path.points[i+1], segment = Entity(); segment.position = vector(CoordinateTransform.toApple(p))
            addSegment(to: segment,vector: .init(x: next.x-p.x,y: next.y-p.y,z: next.z-p.z),radius: 0.008,material: material)
            root.addChild(segment)
        }
        return root
    }
    private func addSegment(to root: Entity, vector domain: Direction3D, radius: Double, material: SimpleMaterial) {
        let delta = vector(CoordinateTransform.toApple(domain)), length = simd_length(delta)
        guard length > 1e-7 else { return }
        let model = ModelEntity(mesh: cylinderMesh(),materials: [material]); model.scale = [Float(radius),length,Float(radius)]
        model.position = delta/2; model.orientation = simd_quatf(from: [0,1,0],to: delta/length); root.addChild(model)
    }
    private func boxMesh() -> MeshResource { if let box { return box }; let value = MeshResource.generateBox(size: 1); box = value; return value }
    private func sphereMesh() -> MeshResource { if let sphere { return sphere }; let value = MeshResource.generateSphere(radius: 1); sphere = value; return value }
    private func cylinderMesh() -> MeshResource { if let cylinder { return cylinder }; let value = MeshResource.generateCylinder(height: 1,radius: 1); cylinder = value; return value }
    private func coneMesh() -> MeshResource { if let cone { return cone }; let value = MeshResource.generateCone(height: 1,radius: 1); cone = value; return value }
    func clearCaches() { box = nil; sphere = nil; cylinder = nil; cone = nil; palette.clear() }
    private func vector(_ p: Position3D) -> SIMD3<Float> { [Float(p.x),Float(p.y),Float(p.z)] }
    private func vector(_ d: Direction3D) -> SIMD3<Float> { [Float(d.x),Float(d.y),Float(d.z)] }
}
