import Foundation
import RealityKit
import SimuCore

/// One immutable mesh / ModelEntity per path, at most 64 entities. No per-segment Entity or ticker.
@available(macOS 15, iOS 18, *) @MainActor
struct AirflowPathRenderer {
    static func entity(path: RoomOverlayPath, material: SimpleMaterial) throws -> Entity {
        guard let data = path.meshData else { throw ProjectDataError.contract("路径 mesh 数组尚未在后台准备；二维路径仍可查看。") }
        var descriptor = MeshDescriptor(name: "native-preview/" + path.id)
        descriptor.positions = .init(data.positions)
        descriptor.normals = .init(data.normals)
        descriptor.primitives = .triangles(data.indices)
        let entity = ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [material])
        entity.name = "overlay/" + path.id
        return entity
    }
}
