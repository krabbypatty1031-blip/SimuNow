import Foundation

public enum L2BoundaryError: Error, Equatable, Sendable {
    case incompleteProject
}

public struct L2HeatSource: Equatable, Sendable {
    public var name: String
    public var watts: Double
}

public struct L2Terminal: Equatable, Sendable {
    public var id: String
    public var wall: String
    public var s0: Double
    public var s1: Double
    public var z0: Double
    public var z1: Double
}

/// L2 inlet/gain DTO. Not a mesh, field, or quality.pass record.
public struct L2Boundary: Equatable, Sendable {
    public var supplyTemperatureC: Double
    public var setpointC: Double
    public var supply: L2Terminal
    public var returnTerminal: L2Terminal
    public var outdoorAirM3s: Double
    /// Recirculated return = supply − outdoor. Not a measured return-air meter.
    public var recirculatedAirM3s: Double
    public var windowHeatFluxWm2: Double
    /// EnergyPlus day-mean opaque conduction into the zone. Nil when L1 omitted it.
    public var opaqueHeatW: Double?
    public var lightingW: Double
    public var equipmentW: Double
    public var occupantSensibleW: Double
    public var occupantCount: Double
    public var heatSources: [L2HeatSource]
    public var omitted: [String]
}

public enum L2BoundaryMapping {
    /// Supply T comes from L1 or the HVAC coil setting, never the zone setpoint.
    public static func map(draft: ProjectDraft, l1: SimulationResult?) throws -> L2Boundary {
        guard let occupancy = draft.occupancy, let hvac = draft.hvac, let geometry = draft.geometry else {
            throw L2BoundaryError.incompleteProject
        }
        let supply = l1?.supplyTemperatureC ?? hvac.supplyTemperatureC.value
        let windows = geometry.openings.filter { $0.kind == .window }
        let windowArea = windows.reduce(0.0) { $0 + $1.patchAreaM2 }
        let draftWindowWatts = windows.reduce(0.0) { $0 + ($1.heatFluxWm2?.value ?? 0) * $1.patchAreaM2 }
        let l1Window = l1?.metric(named: "window_heat_w")
        let l1Opaque = l1?.metric(named: "opaque_heat_w")
        let windowFlux: Double
        if let l1Window, !l1Window.omitted, let watts = l1Window.value, windowArea > 0 {
            windowFlux = watts / windowArea
        } else if windowArea > 0 {
            windowFlux = draftWindowWatts / windowArea
        } else {
            windowFlux = geometry.openings.first(where: { $0.kind == .window })?.heatFluxWm2?.value ?? 0
        }
        let opaqueHeat = (l1Opaque?.omitted == false) ? l1Opaque?.value : nil
        let occupantCount = occupancy.occupantCount.value
        // Per-person sensible × count once. Seats locate people; they are not a second watt source.
        let occupantSensible = occupantCount * occupancy.occupantSensibleW.value
        let outdoor = hvac.outdoorAirM3s.value
        let supplyFlow = hvac.supplyAirflowM3s.value
        return L2Boundary(
            supplyTemperatureC: supply,
            setpointC: hvac.setpointC.value,
            supply: terminal(hvac.supply),
            returnTerminal: terminal(hvac.returnTerminal),
            outdoorAirM3s: outdoor,
            recirculatedAirM3s: max(0, supplyFlow - outdoor),
            windowHeatFluxWm2: windowFlux,
            opaqueHeatW: opaqueHeat,
            lightingW: occupancy.lightingW.value,
            equipmentW: occupancy.equipmentW.value,
            occupantSensibleW: occupantSensible,
            occupantCount: occupantCount,
            heatSources: [
                L2HeatSource(name: "occupants", watts: occupantSensible),
                L2HeatSource(name: "lighting", watts: occupancy.lightingW.value),
                L2HeatSource(name: "equipment", watts: occupancy.equipmentW.value)
            ],
            omitted: opaqueHeat == nil ? ["envelope_u_value"] : []
        )
    }

    private static func terminal(_ patch: AirTerminal) -> L2Terminal {
        L2Terminal(
            id: patch.id,
            wall: patch.wall.rawValue,
            s0: patch.s0.value,
            s1: patch.s1.value,
            z0: patch.z0.value,
            z1: patch.z1.value
        )
    }
}
