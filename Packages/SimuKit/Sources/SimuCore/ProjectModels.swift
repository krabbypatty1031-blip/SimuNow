import Foundation

/// Public wire models use metres and a right-handed, Z-up coordinate system.
public struct Position3D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public enum ParameterSource: String, Codable, Sendable {
    case scan, measured, manufacturer, user, preset, assumed
}

public enum SpaceType: String, Codable, CaseIterable, Sendable {
    case office, classroom, home, publicSpace
}

/// P0 envelope only. Geometry, HVAC and occupancy are specified in Plans/04-data-contracts.md.
/// A draft is not a runnable physical model.
public struct ProjectDraft: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public var id: UUID
    public var name: String
    public var spaceType: SpaceType
    public let lengthUnit: String
    public let coordinateSystem: String

    public init(id: UUID = UUID(), name: String, spaceType: SpaceType = .office) {
        self.schemaVersion = 1
        self.id = id
        self.name = name
        self.spaceType = spaceType
        self.lengthUnit = "m"
        self.coordinateSystem = "rightHandedZUp"
    }
}
