import Foundation
import Testing
@testable import SimuCore

@Test func officeTemplateHasSourcesAndCompletePhysicalModel() throws {
    let template = try ProjectTemplates.office(from: templatesDirectory())
    #expect(template.project.hasCompletePhysicalModel)
    #expect(template.project.spaceType == .office)
    #expect(template.project.hvac != nil)
    #expect(everyQuantityHasSource(template.project))
    #expect(template.project.listedAssumptions().contains { $0.note == "omitted: furniture_boxes" })
    #expect(template.lockedAssumptions.contains("omitted: envelope_u_value"))
    let window = try #require(template.project.geometry?.openings.first)
    #expect(abs((window.s1.value - window.s0.value) - 1.5) < 1e-9)
}

@Test func classroomTemplateSharesSchemaAndHasDenserSeats() throws {
    let office = try ProjectTemplates.office(from: templatesDirectory())
    let classroom = try ProjectTemplates.classroom(from: templatesDirectory())
    #expect(classroom.project.spaceType == .classroom)
    #expect(classroom.project.hasCompletePhysicalModel)
    #expect(everyQuantityHasSource(classroom.project))
    let classroomSeats = classroom.project.occupancy?.seats.map(\.id) ?? []
    let officeSeats = office.project.occupancy?.seats.map(\.id) ?? []
    #expect(Set(classroomSeats).count == classroomSeats.count)
    #expect(classroomSeats.count >= officeSeats.count)
    #expect(classroom.project.geometry?.sizeX.value != office.project.geometry?.sizeX.value
        || (classroom.project.occupancy?.occupantCount.value ?? 0) > (office.project.occupancy?.occupantCount.value ?? 0))
}

@Test func editingCurrentRoomDoesNotMutateFrozenBaseline() throws {
    let template = try ProjectTemplates.office(from: templatesDirectory())
    var session = template.instantiate()
    let baselineSize = try #require(session.baseline.geometry?.sizeX.value)
    _ = session.current.applyRoomSize(x: 7, y: 6, z: 2.8, source: .user)
    #expect(session.current.geometry?.sizeX.value == 7)
    #expect(session.baseline.geometry?.sizeX.value == baselineSize)
    #expect(session.current.id != session.baseline.id)
    #expect(session.baselineScenarioID != session.current.id)
}

@Test func templateOverrideCatalogMatchesJSON() throws {
    let template = try ProjectTemplates.office(from: templatesDirectory())
    #expect(template.overridable.contains("hvac.setpointC"))
    #expect(template.overridable.contains("occupancy.occupantCount"))
    #expect(template.lockedAssumptions.contains("omitted: envelope_u_value"))
    #expect(template.lockedAssumptions.contains("omitted: weather_file"))
}

@Test func bundledTemplatesLoadWithoutRepositoryURL() throws {
    let office = try ProjectTemplates.bundled(named: "office")
    #expect(office.project.spaceType == .office)
    #expect(office.project.hasCompletePhysicalModel)
    let classroom = try ProjectTemplates.bundled(named: "classroom")
    #expect(classroom.project.spaceType == .classroom)
    #expect(classroom.project.hasCompletePhysicalModel)
}

@Test func bundledTemplatesMatchRepositoryFixtures() throws {
    #expect(try ProjectTemplates.bundled(named: "office") == ProjectTemplates.office(from: templatesDirectory()))
    #expect(try ProjectTemplates.bundled(named: "classroom") == ProjectTemplates.classroom(from: templatesDirectory()))
}

@Test func unknownBundledTemplateThrows() {
    #expect(throws: ProjectTemplatesError.unknownTemplate("garage")) {
        try ProjectTemplates.bundled(named: "garage")
    }
}

@Test func p1MappingUsesWindowPatchAreaNotWallWidth() throws {
    let template = try ProjectTemplates.office(from: templatesDirectory())
    let mapped = try P1RoomMapping.map(template.project)
    #expect(abs(mapped.windowAreaM2 - 1.5 * 1.3) < 1e-9)
    #expect(abs(mapped.windowAreaM2 - 6 * 1.3) > 0.1)
    #expect(mapped.sizeXM == 6)
    #expect(mapped.sizeYM == 6)
    #expect(mapped.sizeZM == 2.8)
    #expect(mapped.supplyTemperatureC == 16)
    #expect(mapped.supply.z0M == 2.48)
    #expect(mapped.returnTerminal.z0M == 1.85)
    #expect(mapped.window.s0M == 2.25)
    #expect(mapped.window.s1M == 3.75)
    #expect(mapped.window.z0M == 0.9)
    #expect(mapped.window.heatFluxWm2 == 80)
    #expect(mapped.gains.occupantCount == 8)
    #expect(mapped.gains.lightingW == 180)
    #expect(mapped.gains.equipmentW == 400)
    #expect(mapped.seats.map(\.id) == ["S1", "S2", "S3", "S4"])
    #expect(mapped.seats.first?.xM == 1.5)
    #expect(mapped.seatIDs == ["S1", "S2", "S3", "S4"])
    #expect(mapped.omitted.contains("l1.ua_opaque_w_k"))
    #expect(mapped.omitted.contains("weather_file"))
    #expect(mapped.includesQualityPass == false)
}

private func templatesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/templates")
}

private func everyQuantityHasSource(_ draft: ProjectDraft) -> Bool {
    guard let geometry = draft.geometry, let occupancy = draft.occupancy, let hvac = draft.hvac else {
        return false
    }
    var quantities = [
        geometry.sizeX, geometry.sizeY, geometry.sizeZ, geometry.northYawDegrees,
        occupancy.occupantCount, occupancy.occupantSensibleW, occupancy.lightingW, occupancy.equipmentW,
        hvac.setpointC, hvac.supplyTemperatureC, hvac.supplySpeedMs, hvac.supplyAirflowM3s,
        hvac.outdoorAirM3s, hvac.cop
    ]
    if let comfort = occupancy.comfort {
        quantities.append(contentsOf: [comfort.mrtC, comfort.rhPct, comfort.clo, comfort.met])
    }
    for opening in geometry.openings {
        quantities.append(contentsOf: [opening.s0, opening.s1, opening.z0, opening.z1])
    }
    return quantities.allSatisfy { !$0.source.rawValue.isEmpty }
}
