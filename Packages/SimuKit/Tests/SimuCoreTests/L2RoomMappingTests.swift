import Foundation
import Testing
import SimuCore

@Test func officeL2RoomUsesSupplyTemperatureNotSetpoint() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let room = try L2RoomMapping.map(draft: draft)
    #expect(room.sizeXM == 6)
    #expect(room.sizeYM == 6)
    #expect(room.sizeZM == 2.8)
    #expect(room.supplyTemperatureC == 16)
    #expect(room.setpointC == 26)
    #expect(room.supplyTemperatureC != room.setpointC)
    #expect(room.supplySpeedMs == 1.2)
    #expect(room.occupantCount == 8)
    #expect(room.seats.count == 8)
    #expect(room.occupantCount == Double(room.seats.count))
    #expect(room.seatHeightM == 1.1)
}

@Test func officeL2RoomOmitsFurnitureEnvelopeAndQualityPass() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let room = try L2RoomMapping.map(draft: draft)
    #expect(room.assumptions.contains("omitted: furniture_boxes"))
    #expect(room.assumptions.contains("omitted: envelope_u_value"))
    #expect(room.omitted.contains("envelope_u_value"))
    #expect(room.omitted.contains("quality.pass"))
    #expect(!room.includesQualityPass)
    #expect(room.outdoorAirM3s == 0.02)
    #expect(abs(room.recirculatedAirM3s - 0.088) < 1e-9)
}

@Test func changingOccupantCountKeepsPeopleAndSeatsEqual() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.applyOccupantCount(3, source: .user).isEmpty)
    let changed = try L2RoomMapping.map(draft: draft)
    #expect(changed.occupantCount == 3)
    #expect(changed.seats.count == 3)
    #expect(changed.occupantCount == Double(changed.seats.count))
    // ADR-012: per-person sensible heat is 57 W; latent (13) stays L1-only.
    #expect(changed.occupantSensibleW == 3 * 57)
}

@Test func changingSupplySpeedChangesMappedSpeed() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.applySupplySpeedMs(0.8, source: .user).isEmpty)
    let room = try L2RoomMapping.map(draft: draft)
    #expect(room.supplySpeedMs == 0.8)
    #expect(room.supplyTemperatureC == 16)
}

@Test func currentL1EnvelopeLeavesAssumptionsHonest() throws {
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
    let room = try L2RoomMapping.map(draft: draft, l1: l1)
    #expect(!room.assumptions.contains("omitted: envelope_u_value"))
    #expect(room.assumptions.contains("opaque envelope heat is the EnergyPlus day mean, spread on the walls patch"))
    #expect(room.assumptions.contains("window flux is the EnergyPlus day mean, spread by glazed area"))
    #expect(!room.omitted.contains("envelope_u_value"))
}
