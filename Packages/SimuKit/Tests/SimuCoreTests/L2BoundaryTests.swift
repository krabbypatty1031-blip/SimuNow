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
    #expect(mapped.occupantSensibleW == 8 * 70)
    #expect(mapped.occupantCount == 8)
    #expect(mapped.heatSources.filter { $0.name == "occupants" }.count == 1)
    let occupantTotal = mapped.heatSources.filter { $0.name == "occupants" }.map(\.watts).reduce(0, +)
    #expect(occupantTotal == 560)
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
