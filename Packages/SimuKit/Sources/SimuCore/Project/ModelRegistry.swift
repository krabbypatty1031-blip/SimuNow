import Foundation

public struct GeometryBounds: Equatable, Sendable {
    public let origin: Position3D
    public let size: Position3D
    public init(origin: Position3D, size: Position3D) { self.origin = origin; self.size = size }
    public func contains(_ point: Position3D, tolerance: Double = 1e-6) -> Bool {
        zip([point.x,point.y,point.z], zip([origin.x,origin.y,origin.z], [size.x,size.y,size.z])).allSatisfy { p, pair in
            p >= pair.0 - tolerance && p <= pair.0 + pair.1 + tolerance
        }
    }
    public func intersects(_ other: GeometryBounds, tolerance: Double = 1e-6) -> Bool {
        zip(zip([origin.x,origin.y,origin.z],[size.x,size.y,size.z]), zip([other.origin.x,other.origin.y,other.origin.z],[other.size.x,other.size.y,other.size.z])).allSatisfy { a,b in
            min(a.0+a.1,b.0+b.1) - max(a.0,b.0) > tolerance
        }
    }
}
public protocol ModelPayload: Codable, Sendable {
    static var category: String { get }
    static var kind: String { get }
    static var payloadVersion: Int { get }
    static var wireSchema: JSONValue { get }
    func geometryBounds() -> GeometryBounds?
    func validate(at path: String) -> [ValidationIssue]
}
public extension ModelPayload {
    static var payloadVersion: Int { 1 }
    func geometryBounds() -> GeometryBounds? { nil }
    func validate(at path: String) -> [ValidationIssue] { [] }
}

/// Geometry implementations own containment, opening extents and collision queries.
public protocol GeometryPayload: ModelPayload {
    func contains(_ point: Position3D, tolerance: Double) -> Bool
    func surfaceExtent(_ face: SurfaceFace) -> (Double, Double)?
    func intersects(_ other: any GeometryPayload, tolerance: Double) -> Bool
}
/// An explicit reusable strategy for the first axis-aligned shapes.
public protocol AxisAlignedGeometryPayload: GeometryPayload {}
public extension AxisAlignedGeometryPayload {
    func contains(_ point: Position3D, tolerance: Double) -> Bool { geometryBounds()?.contains(point,tolerance:tolerance) ?? false }
    func surfaceExtent(_ face: SurfaceFace) -> (Double,Double)? {
        guard let b = geometryBounds() else { return nil }
        switch face {
        case .xMin,.xMax: return (b.size.y,b.size.z)
        case .yMin,.yMax: return (b.size.x,b.size.z)
        case .floor,.ceiling: return (b.size.x,b.size.y)
        }
    }
    func intersects(_ other: any GeometryPayload, tolerance: Double) -> Bool {
        guard let a = geometryBounds(), let b = other.geometryBounds() else { return false }
        return a.intersects(b,tolerance:tolerance)
    }
}

public struct ModelRegistration: Sendable {
    public let category: String
    public let kind: String
    public let version: Int
    public let schema: JSONValue
    let decode: @Sendable (JSONValue) throws -> any ModelPayload
    public init<T: ModelPayload>(_ type: T.Type) {
        category = T.category; kind = T.kind; version = T.payloadVersion; schema = T.wireSchema
        decode = { try JSONTreeCoding.decode(T.self, from: $0) }
    }
}
public struct ModelRegistry: Sendable {
    public let registrations: [ModelRegistration]
    private let entries: [String: ModelRegistration]
    public init(_ registrations: [ModelRegistration]) throws {
        var entries: [String: ModelRegistration] = [:]
        for r in registrations {
            let key = Self.key(r.category,r.kind,r.version)
            guard entries[key] == nil else { throw ProjectDataError.duplicateRegistration(key) }
            entries[key] = r
        }
        self.registrations = registrations; self.entries = entries
    }
    private static func key(_ category: String,_ kind: String,_ version: Int) -> String { "\(category)|\(kind)|\(version)" }
    public func registration(category: String, record: ExtensionRecord) -> ModelRegistration? { entries[Self.key(category,record.kind,record.payloadVersion)] }
    public func resolve(category: String, record: ExtensionRecord) throws -> (any ModelPayload)? {
        guard let registration = registration(category: category, record: record) else { return nil }
        try WireSchema.validate(record.payload, schema: registration.schema)
        let payload = try registration.decode(record.payload)
        if ["room","obstacle"].contains(category), !(payload is any GeometryPayload) {
            throw ProjectDataError.contract("Registered geometry must provide geometry queries")
        }
        return payload
    }
    public static let builtIn: ModelRegistry = {
        do { return try standard() }
        catch { preconditionFailure("Invalid built-in model registry: \(error)") }
    }()
    public static func standard() throws -> ModelRegistry {
        try ModelRegistry([ModelRegistration(RectangularRoom.self),ModelRegistration(BoxObstacle.self),ModelRegistration(SingleSplit.self)])
    }
}
public extension ExtensionRecord {
    init<T: ModelPayload>(_ model: T) throws {
        self.init(kind: T.kind, payloadVersion: T.payloadVersion, payload: try JSONTreeCoding.encode(model))
        try WireSchema.validate(payload, schema: T.wireSchema)
    }
    func resolved<T: ModelPayload>(as type: T.Type, registry: ModelRegistry) throws -> T? {
        try registry.resolve(category: T.category, record: self) as? T
    }
}
extension RectangularRoom: AxisAlignedGeometryPayload {
    public static let category = "room"
    public static let kind = "simunow.geometry.rectangularRoom"
    public static var wireSchema: JSONValue { ContractSchemas.payload("RectangularRoom") }
    public func geometryBounds() -> GeometryBounds? {
        guard let w = dimensions.width.value, let d = dimensions.depth.value, let h = dimensions.height.value else { return nil }
        return GeometryBounds(origin: .init(x: 0,y: 0,z: 0),size: .init(x: w,y: d,z: h))
    }
}
extension BoxObstacle: AxisAlignedGeometryPayload {
    public static let category = "obstacle"
    public static let kind = "simunow.geometry.box"
    public static var wireSchema: JSONValue { ContractSchemas.payload("BoxObstacle") }
    public func geometryBounds() -> GeometryBounds? {
        guard let w = dimensions.width.value, let d = dimensions.depth.value, let h = dimensions.height.value else { return nil }
        return GeometryBounds(origin: origin,size: .init(x: w,y: d,z: h))
    }
}
extension SingleSplit: ModelPayload {
    public static let category = "hvac"
    public static let kind = "simunow.hvac.singleSplit"
    public static var wireSchema: JSONValue { ContractSchemas.payload("SingleSplit") }
}
