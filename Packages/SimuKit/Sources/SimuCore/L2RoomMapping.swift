import Foundation

public enum L2RoomMappingError: Error, Equatable, Sendable {
    case incompleteProject
}

/// P1-shaped L2 room. Not a solved field and must not carry quality.pass.
public struct L2MappedRoom: Equatable, Sendable {
    public var name: String
    public var sizeXM: Double
    public var sizeYM: Double
    public var sizeZM: Double
    public var supplyTemperatureC: Double
    public var setpointC: Double
    public var supplySpeedMs: Double
    public var occupantCount: Double
    public var occupantSensibleW: Double
    public var seats: [P1MappedSeat]
    public var seatHeightM: Double
    public var outdoorAirM3s: Double
    public var recirculatedAirM3s: Double
    public var assumptions: [String]
    public var omitted: [String]
    public let includesQualityPass: Bool
}

public enum L2RoomMapping {
    /// Supply T comes from the L2 boundary (coil), never the zone setpoint.
    public static func map(draft: ProjectDraft, l1: SimulationResult? = nil) throws -> L2MappedRoom {
        let boundary = try L2BoundaryMapping.map(draft: draft, l1: l1)
        guard let geometry = draft.geometry, let occupancy = draft.occupancy else {
            throw L2RoomMappingError.incompleteProject
        }
        let seats = occupancy.seats.map {
            P1MappedSeat(id: $0.id, xM: $0.position.x, yM: $0.position.y, zM: $0.position.z)
        }
        let seatHeight = seats.first?.zM ?? 1.1
        let opaqueFromL1 = boundary.opaqueHeatW != nil
        let windowFromL1 = l1?.metric(named: "window_heat_w").map { !$0.omitted && $0.value != nil } ?? false
        return L2MappedRoom(
            name: draft.name,
            sizeXM: geometry.sizeX.value,
            sizeYM: geometry.sizeY.value,
            sizeZM: geometry.sizeZ.value,
            supplyTemperatureC: boundary.supplyTemperatureC,
            setpointC: boundary.setpointC,
            supplySpeedMs: draft.hvac?.supplySpeedMs.value ?? 0,
            occupantCount: boundary.occupantCount,
            occupantSensibleW: boundary.occupantSensibleW,
            seats: seats,
            seatHeightM: seatHeight,
            outdoorAirM3s: boundary.outdoorAirM3s,
            recirculatedAirM3s: boundary.recirculatedAirM3s,
            assumptions: [
                "omitted: furniture_boxes",
                opaqueFromL1
                    ? "opaque envelope heat is the EnergyPlus day mean, spread on the walls patch"
                    : "omitted: envelope_u_value",
                windowFromL1
                    ? "window flux is the EnergyPlus day mean, spread by glazed area"
                    : "window flux is the draft assumption until a current L1 result exists",
                "P1 first-version L2 case has no furniture boxes",
                "wall temperatures are not invented from UA"
            ],
            omitted: [
                opaqueFromL1 ? nil : "envelope_u_value",
                "quality.pass",
                "furniture_boxes"
            ].compactMap { $0 },
            includesQualityPass: false
        )
    }
}
