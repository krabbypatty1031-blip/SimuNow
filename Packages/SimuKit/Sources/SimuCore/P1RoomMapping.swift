import Foundation

public enum P1MappingError: Error, Equatable, Sendable {
    case incompleteProject
}

public struct P1MappedPatch: Equatable, Sendable {
    public var wall: String
    public var s0M: Double
    public var s1M: Double
    public var z0M: Double
    public var z1M: Double
}

public struct P1MappedWindow: Equatable, Sendable {
    public var wall: String
    public var s0M: Double
    public var s1M: Double
    public var z0M: Double
    public var z1M: Double
    public var heatFluxWm2: Double
    public var areaM2: Double
}

public struct P1MappedGains: Equatable, Sendable {
    public var occupantCount: Double
    public var occupantSensibleW: Double
    public var lightingW: Double
    public var equipmentW: Double
}

public struct P1MappedSeat: Equatable, Sendable {
    public var id: String
    public var xM: Double
    public var yM: Double
    public var zM: Double
}

/// Read-only DTO for P1 room keys. This is not a solver case and must not carry quality.pass.
public struct P1MappedRoom: Equatable, Sendable {
    public var name: String
    public var sizeXM: Double
    public var sizeYM: Double
    public var sizeZM: Double
    public var supplyTemperatureC: Double
    public var supplySpeedMs: Double
    public var supply: P1MappedPatch
    public var returnTerminal: P1MappedPatch
    public var window: P1MappedWindow
    public var windowAreaM2: Double
    public var gains: P1MappedGains
    public var occupantCount: Double
    public var seats: [P1MappedSeat]
    public var omitted: [String]
    public let includesQualityPass: Bool

    public var seatIDs: [String] { seats.map(\.id) }
}

public enum P1RoomMapping {
    /// Maps App ProjectDraft to P1-shaped fields. Window area is (s1-s0)*(z1-z0), never wall width.
    public static func map(_ draft: ProjectDraft) throws -> P1MappedRoom {
        guard let geometry = draft.geometry, let occupancy = draft.occupancy, let hvac = draft.hvac else {
            throw P1MappingError.incompleteProject
        }
        guard let opening = geometry.openings.first(where: { $0.kind == .window }) else {
            throw P1MappingError.incompleteProject
        }
        let window = P1MappedWindow(
            wall: opening.wall.rawValue,
            s0M: opening.s0.value,
            s1M: opening.s1.value,
            z0M: opening.z0.value,
            z1M: opening.z1.value,
            heatFluxWm2: opening.heatFluxWm2?.value ?? 0,
            areaM2: opening.patchAreaM2
        )
        return P1MappedRoom(
            name: draft.name,
            sizeXM: geometry.sizeX.value,
            sizeYM: geometry.sizeY.value,
            sizeZM: geometry.sizeZ.value,
            supplyTemperatureC: hvac.supplyTemperatureC.value,
            supplySpeedMs: hvac.supplySpeedMs.value,
            supply: patch(hvac.supply),
            returnTerminal: patch(hvac.returnTerminal),
            window: window,
            windowAreaM2: window.areaM2,
            gains: P1MappedGains(
                occupantCount: occupancy.occupantCount.value,
                occupantSensibleW: occupancy.occupantSensibleW.value,
                lightingW: occupancy.lightingW.value,
                equipmentW: occupancy.equipmentW.value
            ),
            occupantCount: occupancy.occupantCount.value,
            seats: occupancy.seats.map {
                P1MappedSeat(id: $0.id, xM: $0.position.x, yM: $0.position.y, zM: $0.position.z)
            },
            omitted: [
                "l1.ua_opaque_w_k",
                "l1.ua_window_w_k",
                "l1.shgc",
                "weather_file",
                "quality.pass"
            ],
            includesQualityPass: false
        )
    }

    private static func patch(_ terminal: AirTerminal) -> P1MappedPatch {
        P1MappedPatch(
            wall: terminal.wall.rawValue,
            s0M: terminal.s0.value,
            s1M: terminal.s1.value,
            z0M: terminal.z0.value,
            z1M: terminal.z1.value
        )
    }
}
