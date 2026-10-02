import Foundation
import Testing
import SimuCore
import SimuWorkspace

private func roomEditorFixture() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try ProjectCodec(registry: .builtIn).decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
}
private func roomLength(_ value: Double) -> Length { .known(value: value, source: .init(kind: .user)) }

@Test func roomCreationKeepsUnknownsAndSixStableSurfaces() throws {
    let draft = RoomDraft()
    let first = try draft.room(), second = try draft.room()
    #expect(first == second)
    #expect(first.surfaces.count == 6 && Set(first.surfaces.map(\.face)) == Set(SurfaceFace.allCases))
    let project = try RoomEditing.createProject(name: "Draft office", spaceType: .office, room: first)
    let report = try ProjectValidator().validate(project, registry: .builtIn)
    #expect(report.passes(.projectIntegrity))
    #expect(!report.passes(.inputPreparation))
    #expect(project.scenarios.count == 1)
    #expect(project.scenarios[0].inputs.envelope.surfaces.isEmpty)
    #expect(project.scenarios[0].inputs.environment.weather == nil)
    #expect(try ProjectCodec(registry: .builtIn).decode(ProjectCodec(registry: .builtIn).encode(project)) == project)
}

@Test func importedRoomErrorsCanBeRepairedWithoutIntroducingNewErrors() throws {
    var project = try roomEditorFixture()
    let roomID = project.geometry.rooms[0].id
    // Two independent imported issues: a door outside its wall and an invalid HVAC direction.
    project.geometry.rooms[0].openings[0].offsetU = roomLength(100)
    project.scenarios[0].inputs.hvac[0].ports[0].direction.x = 2
    let imported = try ProjectCodec(registry: .builtIn).decode(ProjectCodec(registry: .builtIn).encode(project))
    #expect(try !ProjectValidator().validate(imported, registry: .builtIn).passes(.projectIntegrity))
    var repairedOpening = project.geometry.rooms[0].openings[0]
    repairedOpening.offsetU = roomLength(0.2)
    try RoomEditing.updateOpening(in: &project, roomID: roomID, opening: repairedOpening)
    let remaining = try ProjectValidator().validate(project, registry: .builtIn).issues.filter { $0.blocks.contains(.projectIntegrity) }
    #expect(remaining.count == 1 && remaining[0].code == "direction_unit")
    let dimensions = Dimensions3D(width: roomLength(7), depth: roomLength(4), height: roomLength(3))
    try RoomEditing.updateRoom(in: &project, roomID: roomID, name: "Partly repaired", dimensions: dimensions,
        northAngle: project.geometry.rooms[0].northAngle)
    let beforeRejectedEdit = project
    var invalidOpening = repairedOpening
    invalidOpening.id = UUID(); invalidOpening.offsetU = roomLength(100)
    #expect(throws: RoomEditingError.self) { try RoomEditing.addOpening(in: &project, roomID: roomID, opening: invalidOpening) }
    #expect(project == beforeRejectedEdit)
}

@Test func removingAnOpeningDoesNotReclassifyShiftedExistingError() throws {
    var project = try roomEditorFixture()
    let room = project.geometry.rooms[0]
    project.geometry.rooms[0].openings[1].offsetU = roomLength(100)
    try RoomEditing.deleteOpening(in: &project, roomID: room.id, openingID: room.openings[0].id)
    #expect(project.geometry.rooms[0].openings.count == 1)
    let issue = try ProjectValidator().validate(project, registry: .builtIn).issues.first { $0.code == "opening_bounds" }
    #expect(issue?.entityID == room.openings[1].id)
    #expect(issue?.path == "/geometry/rooms/0/openings/0")
}

@Test func roomRepairCannotTransferAnErrorBetweenScenariosSharingEntityIDs() throws {
    var draft = RoomDraft()
    draft.width = .init(roomLength(6)); draft.depth = .init(roomLength(4)); draft.height = .init(roomLength(3))
    var project = try RoomEditing.createProject(name: "Cross-scenario repair", spaceType: .office, room: draft.room())
    let roomID = project.geometry.rooms[0].id, seatID = UUID()
    project.scenarios[0].inputs.usage.seats = [Seat(id: seatID, roomID: roomID, name: "Seat", position: .init(x: 7, y: 2, z: 1))]
    var candidateScenario = project.scenarios[0]
    candidateScenario.id = UUID(); candidateScenario.name = "Candidate"
    candidateScenario.inputs.usage.seats[0].position = .init(x: 3, y: 3.5, z: 1)
    project.scenarios.append(candidateScenario)
    let original = project
    let originalIssues = try ProjectValidator().validate(project, registry: .builtIn).issues.filter { $0.blocks.contains(.projectIntegrity) }
    #expect(originalIssues.count == 1)
    #expect(originalIssues[0].code == "point_bounds" && originalIssues[0].path.hasPrefix("/scenarios/0/"))
    // Widening fixes the baseline seat, while reducing depth would invalidate the copied seat.
    // The same seat UUID and field path cannot make this a continuation of the old error.
    #expect(throws: RoomEditingError.self) {
        try RoomEditing.updateRoom(in: &project, roomID: roomID, name: "Changed",
            dimensions: .init(width: roomLength(8), depth: roomLength(3), height: roomLength(3)),
            northAngle: draft.northAngle.parameter(as: AngleTag.self, range: .northBearing))
    }
    #expect(project == original)
}

@Test func roomSizeEditPreservesAllGeometryIdentities() throws {
    var project = try roomEditorFixture()
    let before = project.geometry.rooms[0]
    let dimensions = Dimensions3D(width: roomLength(7), depth: roomLength(5), height: roomLength(3.2))
    try RoomEditing.updateRoom(in: &project, roomID: before.id, name: "Edited office", dimensions: dimensions,
        northAngle: .known(value: 90, source: .init(kind: .user)))
    let after = project.geometry.rooms[0]
    #expect(after.id == before.id && after.surfaces == before.surfaces && after.openings == before.openings)
    #expect(after.northAngle.value == 90)
    #expect(try after.shape.resolved(as: RectangularRoom.self, registry: .builtIn)?.dimensions == dimensions)
}

@Test func roomShrinkChecksOtherScenariosAndLeavesInputUntouched() throws {
    var project = try roomEditorFixture()
    var other = project.scenarios[0]; other.id = UUID(); other.name = "Other"
    other.inputs.usage.seats[0].position.x = 5.5
    other.inputs.usage.seats[0].samples[0].position.x = 5.5
    project.scenarios.append(other)
    let before = project
    #expect(throws: RoomEditingError.self) {
        try RoomEditing.updateRoom(in: &project, roomID: before.geometry.rooms[0].id, name: "smaller",
            dimensions: .init(width: roomLength(5), depth: roomLength(4), height: roomLength(3)),
            northAngle: before.geometry.rooms[0].northAngle)
    }
    #expect(project == before)
}

@Test func openingCRUDMaintainsAllScenarioReferencesAndIdentity() throws {
    var project = try roomEditorFixture()
    var other = project.scenarios[0]; other.id = UUID(); other.name = "Candidate"
    project.scenarios.append(other)
    let room = project.geometry.rooms[0]
    let surfaceID = room.surfaces.first { $0.face == .yMax }!.id
    var opening = Opening(id: UUID(), surfaceID: surfaceID, kind: .window,
        offsetU: roomLength(2), offsetV: roomLength(1), width: roomLength(1), height: roomLength(1))
    try RoomEditing.addOpening(in: &project, roomID: room.id, opening: opening)
    for scenario in project.scenarios {
        #expect(scenario.inputs.envelope.windows.first { $0.openingID == opening.id }?.uValue.value == nil)
        #expect(scenario.inputs.ventilation[0].openings.contains { $0.openingID == opening.id })
    }
    let createdID = opening.id
    opening.kind = .door
    try RoomEditing.updateOpening(in: &project, roomID: room.id, opening: opening)
    #expect(project.geometry.rooms[0].openings.last?.id == createdID)
    for scenario in project.scenarios {
        #expect(!scenario.inputs.envelope.windows.contains { $0.openingID == opening.id })
        #expect(scenario.inputs.ventilation[0].openings.contains { $0.openingID == opening.id })
    }
    opening.kind = .window
    try RoomEditing.updateOpening(in: &project, roomID: room.id, opening: opening)
    #expect(project.scenarios.allSatisfy { $0.inputs.envelope.windows.filter { $0.openingID == opening.id }.count == 1 })
    try RoomEditing.deleteOpening(in: &project, roomID: room.id, openingID: opening.id)
    #expect(!project.geometry.rooms[0].openings.contains { $0.id == opening.id })
    for scenario in project.scenarios {
        #expect(!scenario.inputs.envelope.windows.contains { $0.openingID == opening.id })
        #expect(!scenario.inputs.ventilation[0].openings.contains { $0.openingID == opening.id })
    }
    #expect(try ProjectValidator().validate(project, registry: .builtIn).passes(.projectIntegrity))
}

@Test func openingOutOfBoundsAndOverlapFailAtomically() throws {
    var project = try roomEditorFixture()
    let before = project, room = project.geometry.rooms[0]
    var opening = room.openings[0]
    opening.id = UUID()
    #expect(throws: RoomEditingError.self) { try RoomEditing.addOpening(in: &project, roomID: room.id, opening: opening) }
    #expect(project == before)
    opening.offsetU = roomLength(100)
    #expect(throws: RoomEditingError.self) { try RoomEditing.addOpening(in: &project, roomID: room.id, opening: opening) }
    #expect(project == before)
    opening.offsetU = roomLength(2); opening.surfaceID = UUID()
    #expect(throws: RoomEditingError.self) { try RoomEditing.addOpening(in: &project, roomID: room.id, opening: opening) }
    #expect(project == before)
}

@Test func roomEditorDoesNotOverwriteUnsupportedShape() throws {
    var project = try roomEditorFixture()
    project.geometry.rooms[0].shape = .init(kind: "future.room", payloadVersion: 99, payload: .object(["keep": .bool(true)]))
    let before = project
    #expect(throws: RoomEditingError.unsupportedShape) { _ = try RoomDraft(room: project.geometry.rooms[0]) }
    #expect(throws: RoomEditingError.unsupportedShape) {
        try RoomEditing.updateRoom(in: &project, roomID: project.geometry.rooms[0].id, name: "new",
            dimensions: .init(width: roomLength(6), depth: roomLength(4), height: roomLength(3)),
            northAngle: .unknown(reason: "not surveyed"))
    }
    #expect(project == before)
}
