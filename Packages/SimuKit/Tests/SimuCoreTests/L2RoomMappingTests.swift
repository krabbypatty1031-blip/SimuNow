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
    #expect(room.seats.count == 4)
    #expect(room.occupantCount != Double(room.seats.count))
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

@Test func changingOccupantCountChangesPeopleNotSeatCount() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    let baseline = try L2RoomMapping.map(draft: draft)
    #expect(draft.applyOccupantCount(3, source: .user).isEmpty)
    let changed = try L2RoomMapping.map(draft: draft)
    #expect(changed.occupantCount == 3)
    #expect(changed.seats.count == baseline.seats.count)
    #expect(changed.occupantCount != Double(changed.seats.count))
    #expect(changed.occupantSensibleW == 3 * 70)
}

@Test func changingSupplySpeedChangesMappedSpeed() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.applySupplySpeedMs(0.8, source: .user).isEmpty)
    let room = try L2RoomMapping.map(draft: draft)
    #expect(room.supplySpeedMs == 0.8)
    #expect(room.supplyTemperatureC == 16)
}
