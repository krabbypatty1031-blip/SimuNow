import Foundation
import SimuCore

public enum RoomSceneMaterial: String, Sendable {
    case wall, floor, door, window, furniture, seat, sample, occupant, equipment, hvac, supply, returnPort,
        control, north, preview, blocked
}
public enum RoomSceneGeometry: Equatable, Sendable {
    case box(size: Position3D)
    case sphere(radius: Double)
    /// Vector and radius in domain metres, beginning at the node position.
    case segment(vector: Displacement3D, radius: Double)
    case arrow(direction: Direction3D, length: Double, radius: Double)
}
public struct RoomSceneNode: Equatable, Sendable, Identifiable {
    public let key: SceneNodeKey
    public let geometry: RoomSceneGeometry
    /// Box/sphere center, segment/arrow start, in right-handed Z-up metres.
    public let position: Position3D
    public let material: RoomSceneMaterial
    public let face: SurfaceFace?
    public let selectable: Bool
    public var id: SceneNodeKey { key }
    public init(
        key: SceneNodeKey, geometry: RoomSceneGeometry, position: Position3D,
        material: RoomSceneMaterial, face: SurfaceFace? = nil, selectable: Bool = true
    ) {
        self.key = key
        self.geometry = geometry
        self.position = position
        self.material = material
        self.face = face
        self.selectable = selectable
    }
}
public struct RoomSceneObject: Equatable, Sendable, Identifiable {
    public let key: SceneObjectKey
    public let title: String
    public let detail: String
    public let target: RoomSceneSelectionTarget?
    public let focusBounds: GeometryBounds?
    public var id: SceneObjectKey { key }
    public init(
        key: SceneObjectKey, title: String, detail: String, target: RoomSceneSelectionTarget?,
        focusBounds: GeometryBounds? = nil
    ) {
        self.key = key
        self.title = title
        self.detail = detail
        self.target = target
        self.focusBounds = focusBounds
    }
}
public struct RoomSceneIssue: Equatable, Sendable, Identifiable {
    public let key: SceneObjectKey?
    public let code: String
    public let message: String
    public var id: String { (key?.id ?? "scene") + ":" + code }
    public init(key: SceneObjectKey?, code: String, message: String) {
        self.key = key
        self.code = code
        self.message = message
    }
}

/// Only values: no file IO, RealityKit, physical calculations or persisted camera state.
public struct SceneDescriptor: Equatable, Sendable {
    public let projectID: UUID
    public let scenarioID: UUID
    public let roomID: UUID?
    public let bounds: GeometryBounds?
    public let nodes: [RoomSceneNode]
    public let objects: [RoomSceneObject]
    public let issues: [RoomSceneIssue]
    public let revision: UInt64
    public init(
        projectID: UUID, scenarioID: UUID, roomID: UUID?, bounds: GeometryBounds?, nodes: [RoomSceneNode],
        objects: [RoomSceneObject], issues: [RoomSceneIssue]
    ) {
        self.projectID = projectID
        self.scenarioID = scenarioID
        self.roomID = roomID
        self.bounds = bounds
        self.nodes = nodes
        self.objects = objects
        self.issues = issues
        // A deterministic display revision, deliberately unrelated to analysis hashing.
        var digest = SceneRevisionDigest()
        digest.add(projectID.uuidString.lowercased())
        digest.add(scenarioID.uuidString.lowercased())
        if let roomID { digest.add(roomID.uuidString.lowercased()) }
        if let bounds {
            digest.add(bounds.origin)
            digest.add(bounds.size)
        }
        for node in nodes {
            digest.add(node.key.id)
            digest.add(node.position)
            digest.add(node.material.rawValue)
            digest.add(node.face?.rawValue ?? "")
            digest.add(node.selectable ? "1" : "0")
            switch node.geometry {
            case .box(let size):
                digest.add("box")
                digest.add(size)
            case .sphere(let radius):
                digest.add("sphere")
                digest.add(radius)
            case .segment(let vector, let radius):
                digest.add("segment")
                digest.add(.init(x: vector.x, y: vector.y, z: vector.z))
                digest.add(radius)
            case .arrow(let direction, let length, let radius):
                digest.add("arrow")
                digest.add(.init(x: direction.x, y: direction.y, z: direction.z))
                digest.add(length)
                digest.add(radius)
            }
        }
        for object in objects {
            digest.add(object.key.id)
            digest.add(object.title)
            digest.add(object.detail)
        }
        for issue in issues {
            digest.add(issue.id)
            digest.add(issue.message)
        }
        revision = digest.value
    }
    public func object(_ key: SceneObjectKey?) -> RoomSceneObject? {
        guard let key else { return nil }
        return objects.first { $0.key == key }
    }
}
private struct SceneRevisionDigest {
    var value: UInt64 = 14_695_981_039_346_656_037
    mutating func add(_ text: String) {
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        value = (value ^ 255) &* 1_099_511_628_211
    }
    mutating func add(_ number: Double) { add(String((number == 0 ? 0 : number).bitPattern, radix: 16)) }
    mutating func add(_ point: Position3D) {
        add(point.x)
        add(point.y)
        add(point.z)
    }
}

/// Display-only immutable paths. The caller owns run identity, freshness and method checks.
public struct RoomOverlayPath: Equatable, Sendable, Identifiable {
    public let id: String
    public let points: [Position3D]
    public let blocked: Bool
    public let meshData: AirflowPathMeshData?
    public init(id: String, points: [Position3D], blocked: Bool = false, meshData: AirflowPathMeshData? = nil)
    {
        self.id = id
        self.points = points
        self.blocked = blocked
        self.meshData = meshData
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.points == rhs.points && lhs.blocked == rhs.blocked
            && (lhs.meshData == nil) == (rhs.meshData == nil)
    }
}
public struct RoomSceneOverlay: Equatable, Sendable {
    public let paths: [RoomOverlayPath]
    public let explanation: String
    public init(paths: [RoomOverlayPath], explanation: String) {
        self.paths = paths
        self.explanation = explanation
    }
    public static let empty = Self(paths: [], explanation: "")
}

extension RoomSceneOverlay {
    public var validationMessage: String? {
        guard paths.count <= 64 else { return "路径超过 64 条显示上限。" }
        guard Set(paths.map(\.id)).count == paths.count else { return "路径显示身份重复。" }
        guard
            paths.allSatisfy({
                !$0.id.isEmpty && $0.points.count >= 2 && $0.points.count <= 129
                    && $0.points.allSatisfy { p in
                        [p.x, p.y, p.z].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
                    }
            })
        else { return "路径点无效或超过每条 128 段显示上限。" }
        return nil
    }
}
