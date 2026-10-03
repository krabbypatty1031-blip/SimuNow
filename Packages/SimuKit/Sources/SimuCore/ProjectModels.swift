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

public enum ParameterSource: String, Codable, CaseIterable, Sendable {
    case scan, measured, manufacturer, user, preset, assumed
}

public enum SpaceType: String, Codable, CaseIterable, Sendable {
    case office, classroom, home, publicSpace
}

/// Measured or assumed scalar. Unit strings are part of the wire contract, not display formatting.
public struct PhysicalQuantity: Codable, Equatable, Sendable {
    public var value: Double
    public var unit: String
    public var source: ParameterSource
    /// Citation or handbook name. Local file paths are not allowed; empty strings are stored as nil.
    public var reference: String?
    /// Half-width or 1σ in the same unit as `value`.
    public var uncertainty: Double?

    public init(
        value: Double,
        unit: String,
        source: ParameterSource,
        reference: String? = nil,
        uncertainty: Double? = nil
    ) {
        self.value = value
        self.unit = unit
        self.source = source
        self.reference = Self.normalizedReference(reference)
        self.uncertainty = uncertainty
    }

    enum CodingKeys: String, CodingKey {
        case value, unit, source, reference, uncertainty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Double.self, forKey: .value)
        unit = try container.decode(String.self, forKey: .unit)
        source = try container.decode(ParameterSource.self, forKey: .source)
        reference = Self.normalizedReference(try container.decodeIfPresent(String.self, forKey: .reference))
        uncertainty = try container.decodeIfPresent(Double.self, forKey: .uncertainty)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(reference, forKey: .reference)
        try container.encodeIfPresent(uncertainty, forKey: .uncertainty)
    }

    private static func normalizedReference(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct RoomGeometry: Codable, Equatable, Sendable {
    public var sizeX: PhysicalQuantity
    public var sizeY: PhysicalQuantity
    public var sizeZ: PhysicalQuantity
    /// 0° means +Y is north in the Z-up plan. Changing this value does not rotate existing s0/s1.
    public var northYawDegrees: PhysicalQuantity
    public var openings: [Opening]
    public var obstacles: [ObstacleBox]
    public var assumptions: [String]

    public init(
        sizeX: PhysicalQuantity,
        sizeY: PhysicalQuantity,
        sizeZ: PhysicalQuantity,
        northYawDegrees: PhysicalQuantity = PhysicalQuantity(value: 0, unit: "deg", source: .assumed),
        openings: [Opening] = [],
        obstacles: [ObstacleBox] = [],
        assumptions: [String] = []
    ) {
        self.sizeX = sizeX
        self.sizeY = sizeY
        self.sizeZ = sizeZ
        self.northYawDegrees = northYawDegrees
        self.openings = openings
        self.obstacles = obstacles
        self.assumptions = assumptions
    }

    enum CodingKeys: String, CodingKey {
        case sizeX, sizeY, sizeZ, northYawDegrees, openings, obstacles, assumptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sizeX = try container.decode(PhysicalQuantity.self, forKey: .sizeX)
        sizeY = try container.decode(PhysicalQuantity.self, forKey: .sizeY)
        sizeZ = try container.decode(PhysicalQuantity.self, forKey: .sizeZ)
        northYawDegrees = try container.decodeIfPresent(PhysicalQuantity.self, forKey: .northYawDegrees)
            ?? PhysicalQuantity(value: 0, unit: "deg", source: .assumed)
        openings = try container.decode([Opening].self, forKey: .openings)
        obstacles = try container.decode([ObstacleBox].self, forKey: .obstacles)
        assumptions = try container.decode([String].self, forKey: .assumptions)
    }

    /// Wall-local `s` runs along Y on xMin/xMax faces and along X on yMin/yMax faces.
    public func span(along wall: WallFace) -> Double {
        switch wall {
        case .xMin, .xMax: sizeY.value
        case .yMin, .yMax: sizeX.value
        }
    }

    public func contains(_ opening: Opening) -> Bool {
        contains(wall: opening.wall, s0: opening.s0.value, s1: opening.s1.value, z0: opening.z0.value, z1: opening.z1.value)
    }

    public func contains(_ terminal: AirTerminal) -> Bool {
        contains(wall: terminal.wall, s0: terminal.s0.value, s1: terminal.s1.value, z0: terminal.z0.value, z1: terminal.z1.value)
    }

    public func contains(_ box: ObstacleBox) -> Bool {
        box.size.x > 0 && box.size.y > 0 && box.size.z > 0
            && box.origin.x >= 0 && box.origin.y >= 0 && box.origin.z >= 0
            && box.origin.x + box.size.x <= sizeX.value
            && box.origin.y + box.size.y <= sizeY.value
            && box.origin.z + box.size.z <= sizeZ.value
    }

    public func containsSeat(_ seat: Seat) -> Bool {
        let p = seat.position
        let insideRoom = p.x > 0 && p.y > 0 && p.z > 0 && p.x < sizeX.value && p.y < sizeY.value && p.z < sizeZ.value
        let insideFurniture = obstacles.contains { box in
            p.x >= box.origin.x && p.x <= box.origin.x + box.size.x
                && p.y >= box.origin.y && p.y <= box.origin.y + box.size.y
                && p.z >= box.origin.z && p.z <= box.origin.z + box.size.z
        }
        return insideRoom && !insideFurniture
    }

    private func contains(wall: WallFace, s0: Double, s1: Double, z0: Double, z1: Double) -> Bool {
        s0 >= 0 && s1 <= span(along: wall) && s0 < s1 && z0 >= 0 && z1 <= sizeZ.value && z0 < z1
    }
}

public enum OpeningKind: String, Codable, CaseIterable, Sendable {
    case window, door
}

public enum WallFace: String, Codable, CaseIterable, Sendable {
    case xMin, xMax, yMin, yMax
}

public struct Opening: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: OpeningKind
    public var wall: WallFace
    /// Distance along the wall from the wall's minimum plan coordinate.
    public var s0: PhysicalQuantity
    public var s1: PhysicalQuantity
    public var z0: PhysicalQuantity
    public var z1: PhysicalQuantity
    public var heatFluxWm2: PhysicalQuantity?

    public init(
        id: String,
        kind: OpeningKind,
        wall: WallFace,
        s0: PhysicalQuantity,
        s1: PhysicalQuantity,
        z0: PhysicalQuantity,
        z1: PhysicalQuantity,
        heatFluxWm2: PhysicalQuantity? = nil
    ) {
        self.id = id
        self.kind = kind
        self.wall = wall
        self.s0 = s0
        self.s1 = s1
        self.z0 = z0
        self.z1 = z1
        self.heatFluxWm2 = heatFluxWm2
    }

    public var patchAreaM2: Double {
        wallPatchAreaM2(s0: s0, s1: s1, z0: z0, z1: z1)
    }
}

public struct ObstacleBox: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var origin: Position3D
    public var size: Position3D
    /// What the user placed (user request 2026-10-04). Drives the schematic
    /// drawing and default footprint; older project files carry no kind and
    /// decode as the original desk box.
    public var kind: FurnitureKind

    public init(id: String, origin: Position3D, size: Position3D, kind: FurnitureKind = .desk) {
        self.id = id
        self.origin = origin
        self.size = size
        self.kind = kind
    }

    /// Old project JSON has no `kind`; decode falls back to `.desk` so
    /// pre-kind files keep loading with their original desk boxes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        origin = try container.decode(Position3D.self, forKey: .origin)
        size = try container.decode(Position3D.self, forKey: .size)
        kind = try container.decodeIfPresent(FurnitureKind.self, forKey: .kind) ?? .desk
    }

    private enum CodingKeys: String, CodingKey {
        case id, origin, size, kind
    }
}

/// Occupied clock window on the representative day. Not an 8760 file and not annual energy.
public struct OccupiedHours: Codable, Equatable, Sendable {
    public var kind: String
    public var start: String
    public var end: String
    public var source: ParameterSource
    public var reference: String?

    public init(
        kind: String = "occupied_hours",
        start: String,
        end: String,
        source: ParameterSource,
        reference: String? = nil
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.source = source
        self.reference = reference
    }

    /// Zero-padded `HH:MM`. `24:00` is only valid as an end clock.
    public static func isValidClock(_ text: String) -> Bool {
        if text == "24:00" { return true }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    public static func minutes(from text: String) -> Int? {
        if text == "24:00" { return 24 * 60 }
        guard isValidClock(text) else { return nil }
        let parts = text.split(separator: ":")
        return (Int(parts[0]) ?? 0) * 60 + (Int(parts[1]) ?? 0)
    }
}

/// Adult-office ISO 7730 inputs the L2 field cannot produce. Missing keys
/// keep PMV omitted; they are never filled with a neutral 0.
public struct ComfortAssumptions: Codable, Equatable, Sendable {
    public var mrtC: PhysicalQuantity
    public var rhPct: PhysicalQuantity
    public var clo: PhysicalQuantity
    public var met: PhysicalQuantity

    public init(
        mrtC: PhysicalQuantity,
        rhPct: PhysicalQuantity,
        clo: PhysicalQuantity,
        met: PhysicalQuantity
    ) {
        self.mrtC = mrtC
        self.rhPct = rhPct
        self.clo = clo
        self.met = met
    }

    /// ADR-013 defaults. MRT is assumed equal to the zone setpoint, not a radiation solve.
    public static let adultOffice = ComfortAssumptions(
        mrtC: PhysicalQuantity(
            value: 26,
            unit: "C",
            source: .assumed,
            reference: "假设等于区设定，不是辐射求解"
        ),
        rhPct: PhysicalQuantity(
            value: 50,
            unit: "%",
            source: .assumed,
            reference: "比赛演示湿度假设，不是房间湿度场"
        ),
        clo: PhysicalQuantity(
            value: 0.5,
            unit: "clo",
            source: .assumed,
            reference: "ISO 7730 夏季轻薄办公着装量级"
        ),
        met: PhysicalQuantity(
            value: 1.2,
            unit: "met",
            source: .assumed,
            reference: "ISO 7730 久坐办公 70 W/m2（1 met = 58.15 W/m2 → 1.2 met）"
        )
    )
}

public struct OccupancyModel: Codable, Equatable, Sendable {
    public var occupantCount: PhysicalQuantity
    public var occupantSensibleW: PhysicalQuantity
    public var lightingW: PhysicalQuantity
    public var equipmentW: PhysicalQuantity
    public var seats: [Seat]
    public var schedule: OccupiedHours?
    /// Optional. A v2 draft that predates this field still decodes.
    public var comfort: ComfortAssumptions?

    public init(
        occupantCount: PhysicalQuantity,
        occupantSensibleW: PhysicalQuantity,
        lightingW: PhysicalQuantity,
        equipmentW: PhysicalQuantity,
        seats: [Seat],
        schedule: OccupiedHours? = nil,
        comfort: ComfortAssumptions? = nil
    ) {
        self.occupantCount = occupantCount
        self.occupantSensibleW = occupantSensibleW
        self.lightingW = lightingW
        self.equipmentW = equipmentW
        self.seats = seats
        self.schedule = schedule
        self.comfort = comfort
    }

    enum CodingKeys: String, CodingKey {
        case occupantCount, occupantSensibleW, lightingW, equipmentW, seats, schedule, comfort
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(occupantCount, forKey: .occupantCount)
        try container.encode(occupantSensibleW, forKey: .occupantSensibleW)
        try container.encode(lightingW, forKey: .lightingW)
        try container.encode(equipmentW, forKey: .equipmentW)
        try container.encode(seats, forKey: .seats)
        try container.encodeIfPresent(schedule, forKey: .schedule)
        try container.encodeIfPresent(comfort, forKey: .comfort)
    }
}

public struct Seat: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var position: Position3D
    public var source: ParameterSource

    public init(id: String, position: Position3D, source: ParameterSource) {
        self.id = id
        self.position = position
        self.source = source
    }
}

public enum HVACKind: String, Codable, Sendable {
    case splitAC
}

public struct HVACModel: Codable, Equatable, Sendable {
    public var kind: HVACKind
    /// Zone setpoint. Never treat this as supply temperature.
    public var setpointC: PhysicalQuantity
    public var supplyTemperatureC: PhysicalQuantity
    public var supplySpeedMs: PhysicalQuantity
    public var supplyAirflowM3s: PhysicalQuantity
    public var supply: AirTerminal
    public var returnTerminal: AirTerminal
    public var outdoorAirM3s: PhysicalQuantity
    public var cop: PhysicalQuantity
    /// System-on window for the representative day. Not a return-air temperature.
    public var schedule: OccupiedHours?

    public init(
        kind: HVACKind = .splitAC,
        setpointC: PhysicalQuantity,
        supplyTemperatureC: PhysicalQuantity,
        supplySpeedMs: PhysicalQuantity,
        supplyAirflowM3s: PhysicalQuantity,
        supply: AirTerminal,
        returnTerminal: AirTerminal,
        outdoorAirM3s: PhysicalQuantity,
        cop: PhysicalQuantity,
        schedule: OccupiedHours? = nil
    ) {
        self.kind = kind
        self.setpointC = setpointC
        self.supplyTemperatureC = supplyTemperatureC
        self.supplySpeedMs = supplySpeedMs
        self.supplyAirflowM3s = supplyAirflowM3s
        self.supply = supply
        self.returnTerminal = returnTerminal
        self.outdoorAirM3s = outdoorAirM3s
        self.cop = cop
        self.schedule = schedule
    }

    enum CodingKeys: String, CodingKey {
        case kind, setpointC, supplyTemperatureC, supplySpeedMs, supplyAirflowM3s
        case supply, returnTerminal, outdoorAirM3s, cop, schedule
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(setpointC, forKey: .setpointC)
        try container.encode(supplyTemperatureC, forKey: .supplyTemperatureC)
        try container.encode(supplySpeedMs, forKey: .supplySpeedMs)
        try container.encode(supplyAirflowM3s, forKey: .supplyAirflowM3s)
        try container.encode(supply, forKey: .supply)
        try container.encode(returnTerminal, forKey: .returnTerminal)
        try container.encode(outdoorAirM3s, forKey: .outdoorAirM3s)
        try container.encode(cop, forKey: .cop)
        try container.encodeIfPresent(schedule, forKey: .schedule)
    }

    /// Compares declared supply volume flow with speed × patch area. Relative tolerance is not a confidence interval.
    public func supplyAirflowMatchesSpeed(relativeTolerance: Double = 0.05) -> Bool {
        let expected = supplySpeedMs.value * supply.patchAreaM2
        let actual = supplyAirflowM3s.value
        if expected == 0 {
            return abs(actual) <= relativeTolerance
        }
        return abs(actual - expected) / expected <= relativeTolerance
    }

    /// Declared flow follows speed × patch area so area/speed edits stay internally consistent.
    public mutating func recomputeSupplyAirflow(source: ParameterSource) {
        supplyAirflowM3s = PhysicalQuantity(
            value: supplySpeedMs.value * supply.patchAreaM2,
            unit: "m3/s",
            source: source
        )
    }
}

public struct AirTerminal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var wall: WallFace
    public var s0: PhysicalQuantity
    public var s1: PhysicalQuantity
    public var z0: PhysicalQuantity
    public var z1: PhysicalQuantity

    public init(
        id: String,
        wall: WallFace,
        s0: PhysicalQuantity,
        s1: PhysicalQuantity,
        z0: PhysicalQuantity,
        z1: PhysicalQuantity
    ) {
        self.id = id
        self.wall = wall
        self.s0 = s0
        self.s1 = s1
        self.z0 = z0
        self.z1 = z1
    }

    public var patchAreaM2: Double {
        wallPatchAreaM2(s0: s0, s1: s1, z0: z0, z1: z1)
    }
}

private func wallPatchAreaM2(
    s0: PhysicalQuantity,
    s1: PhysicalQuantity,
    z0: PhysicalQuantity,
    z1: PhysicalQuantity
) -> Double {
    max(0, s1.value - s0.value) * max(0, z1.value - z0.value)
}

/// P0 envelope plus optional P2 physical partitions. Missing partitions are not solver input.
public struct ProjectDraft: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public var id: UUID
    public var name: String
    public var spaceType: SpaceType
    public let lengthUnit: String
    public let coordinateSystem: String
    public var geometry: RoomGeometry?
    public var occupancy: OccupancyModel?
    public var hvac: HVACModel?
    /// Optional demo tariff. Old drafts omit it; a missing price is not 0 HKD.
    public var costAssumptions: CostAssumptions?

    public init(id: UUID = UUID(), name: String, spaceType: SpaceType = .office) {
        self.schemaVersion = 1
        self.id = id
        self.name = name
        self.spaceType = spaceType
        self.lengthUnit = "m"
        self.coordinateSystem = "rightHandedZUp"
        self.geometry = nil
        self.occupancy = nil
        self.hvac = nil
        self.costAssumptions = nil
    }

    public init(
        id: UUID = UUID(),
        name: String,
        spaceType: SpaceType = .office,
        geometry: RoomGeometry,
        occupancy: OccupancyModel,
        hvac: HVACModel,
        costAssumptions: CostAssumptions? = nil
    ) {
        self.schemaVersion = 2
        self.id = id
        self.name = name
        self.spaceType = spaceType
        self.lengthUnit = "m"
        self.coordinateSystem = "rightHandedZUp"
        self.geometry = geometry
        self.occupancy = occupancy
        self.hvac = hvac
        self.costAssumptions = costAssumptions
    }

    /// True only when geometry, occupancy and HVAC are all present. Does not mean engines can run.
    public var hasCompletePhysicalModel: Bool {
        geometry != nil && occupancy != nil && hvac != nil
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, id, name, spaceType, lengthUnit, coordinateSystem
        case geometry, occupancy, hvac, costAssumptions
    }

    /// Omit missing partitions so v1 identity JSON does not grow null placeholders.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(spaceType, forKey: .spaceType)
        try container.encode(lengthUnit, forKey: .lengthUnit)
        try container.encode(coordinateSystem, forKey: .coordinateSystem)
        try container.encodeIfPresent(geometry, forKey: .geometry)
        try container.encodeIfPresent(occupancy, forKey: .occupancy)
        try container.encodeIfPresent(hvac, forKey: .hvac)
        try container.encodeIfPresent(costAssumptions, forKey: .costAssumptions)
    }

    /// First unused `prefix + n` so adding after a delete cannot overwrite a remaining object.
    public static func nextPrefixedID(prefix: String, existing: [String]) -> String {
        let ids = Set(existing)
        var n = 1
        while ids.contains("\(prefix)\(n)") {
            n += 1
        }
        return "\(prefix)\(n)"
    }
}
