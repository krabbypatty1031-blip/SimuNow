import Foundation
import SimuCore
import simd

public struct AirflowPathMeshData: Equatable, Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
}
/// Pure CPU arrays; production calls this on a detached task before installing RealityKit resources.
public enum AirflowPathMeshBuilder {
    public static func build(_ path: RoomOverlayPath) throws -> AirflowPathMeshData {
        guard (2...129).contains(path.points.count),
            path.points.allSatisfy({ [$0.x, $0.y, $0.z].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } })
        else { throw ProjectDataError.contract("Path mesh requires 2…129 finite domain points") }
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let sides = 8
        let radius: Float = 0.008
        vertices.reserveCapacity((path.points.count - 1) * 34)
        normals.reserveCapacity((path.points.count - 1) * 34)
        indices.reserveCapacity((path.points.count - 1) * 96)
        for (i, p) in path.points.dropLast().enumerated() {
            try Task.checkCancellation()
            func apple(_ p: Position3D) -> SIMD3<Float> {
                let q = CoordinateTransform.toApple(p)
                return [Float(q.x), Float(q.y), Float(q.z)]
            }
            let start = apple(p)
            let end = apple(path.points[i + 1])
            let delta = end - start
            let length = simd_length(delta)
            guard length > 1e-7 else { continue }
            let axis = delta / length
            let helpers: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
            var helper = helpers[0]
            for candidate in helpers.dropFirst()
            where abs(simd_dot(axis, candidate)) < abs(simd_dot(axis, helper)) { helper = candidate }
            let u = simd_normalize(simd_cross(axis, helper))
            let v = simd_cross(axis, u)
            let base = UInt32(vertices.count)
            for ring in [start, end] {
                for n in 0..<sides {
                    let angle = Float(n) * 2 * Float.pi / Float(sides)
                    let normal = u * cos(angle) + v * sin(angle)
                    vertices.append(ring + normal * radius)
                    normals.append(normal)
                }
            }
            for n in 0..<sides {
                let a = base + UInt32(n)
                let b = base + UInt32((n + 1) % sides)
                let c = a + UInt32(sides)
                let d = b + UInt32(sides)
                indices += [a, b, c, b, d, c]
            }
            let capBase = UInt32(vertices.count)
            for (ring, normal) in [(start, -axis), (end, axis)] {
                vertices.append(ring)
                normals.append(normal)
                for n in 0..<sides {
                    let angle = Float(n) * 2 * Float.pi / Float(sides)
                    vertices.append(ring + (u * cos(angle) + v * sin(angle)) * radius)
                    normals.append(normal)
                }
            }
            for n in 0..<sides {
                indices += [capBase, capBase + UInt32((n + 1) % sides + 1), capBase + UInt32(n + 1)]
                let endCap = capBase + UInt32(sides + 1)
                indices += [endCap, endCap + UInt32(n + 1), endCap + UInt32((n + 1) % sides + 1)]
            }
        }
        guard !vertices.isEmpty else { throw ProjectDataError.contract("Path has no drawable segment") }
        return .init(positions: vertices, normals: normals, indices: indices)
    }
}
extension RoomSceneOverlay {
    public func preparedFor3D() throws -> Self {
        if let error = validationMessage { throw ProjectDataError.contract(error) }
        return .init(
            paths: try paths.map { path in
                try Task.checkCancellation()
                return .init(
                    id: path.id, points: path.points, blocked: path.blocked,
                    meshData: try AirflowPathMeshBuilder.build(path))
            }, explanation: explanation)
    }
}
