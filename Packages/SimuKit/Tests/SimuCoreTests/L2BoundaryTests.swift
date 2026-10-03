import Foundation
import Testing
import SimuCore

@Test func boundaryUsesSupplyTemperatureNotSetpoint() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let mapped = try L2BoundaryMapping.map(draft: draft, l1: nil)
    #expect(mapped.supplyTemperatureC == 16)
    #expect(mapped.setpointC == 26)
    #expect(mapped.supplyTemperatureC != mapped.setpointC)
    #expect(mapped.windowHeatFluxWm2 == 80)
    #expect(mapped.lightingW == 180)
    #expect(mapped.equipmentW == 400)
}

@Test func occupantSensibleHeatIsCountedOnce() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let mapped = try L2BoundaryMapping.map(draft: draft, l1: nil)
    // ADR-012: template occupantSensibleW is per-person SENSIBLE heat
    // (57 W, the measured EnergyPlus split of the 70 W activity level);
    // latent heat (13 W) stays an L1-only q_cool term, never in the L2 field.
    #expect(mapped.occupantSensibleW == 8 * 57)
    #expect(mapped.occupantCount == 8)
    #expect(mapped.heatSources.filter { $0.name == "occupants" }.count == 1)
    let occupantTotal = mapped.heatSources.filter { $0.name == "occupants" }.map(\.watts).reduce(0, +)
    #expect(occupantTotal == 456)
    #expect(mapped.omitted.contains("envelope_u_value"))
    #expect(!mapped.omitted.contains("occupants"))
}

@Test func boundaryMapsReturnSeparatelyFromSupplyAndOutdoorAir() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let mapped = try L2BoundaryMapping.map(draft: draft, l1: nil)
    #expect(mapped.returnTerminal.id == "RET1")
    #expect(mapped.returnTerminal.wall == "xMin")
    #expect(mapped.returnTerminal.z0 == 1.85)
    #expect(mapped.supply.id == "SUP1")
    #expect(mapped.supply.z0 == 2.48)
    #expect(mapped.returnTerminal.z0 != mapped.supply.z0)
    #expect(mapped.outdoorAirM3s == 0.02)
    #expect(abs(mapped.recirculatedAirM3s - (0.108 - 0.02)) < 1e-9)
    #expect(mapped.outdoorAirM3s != mapped.recirculatedAirM3s)
}

@Test func currentL1WindowHeatReplacesDraftFlux() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
        draft: draft,
        context: L1DayContext(
            weatherPath: "weather/HK.epw",
            weatherHash: "h",
            coolingLoadW: 6000,
            windowHeatW: 390,
            opaqueHeatW: 200
        )
    )
    let mapped = try L2BoundaryMapping.map(draft: draft, l1: l1)
    // Office glazed area is 1.5 × 1.3 = 1.95 m²; 390 W / 1.95 m² = 200 W/m².
    #expect(abs(mapped.windowHeatFluxWm2 - 200) < 1e-9)
    #expect(mapped.opaqueHeatW == 200)
    #expect(!mapped.omitted.contains("envelope_u_value"))
}

@Test func omittedL1WindowKeepsDraftFluxAndDoesNotInventOpaque() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: UUID(), inputHash: "snap"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let mapped = try L2BoundaryMapping.map(draft: draft, l1: l1)
    #expect(mapped.windowHeatFluxWm2 == 80)
    #expect(mapped.opaqueHeatW == nil)
    #expect(mapped.omitted.contains("envelope_u_value"))
}
