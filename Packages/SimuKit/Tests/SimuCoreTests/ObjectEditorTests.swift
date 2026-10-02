import Foundation
import Testing
import SimuCore
import SimuVisualization
@testable import SimuWorkspace

private func objectEditorFixture() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try ProjectCodec(registry: .builtIn).decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
}
private func editorBox(roomID: UUID, position: Position3D) throws -> Obstacle {
    let dimension = Length.known(value: 0.3, source: .init(kind: .user))
    return try .init(id: UUID(), roomID: roomID, name: "Test box", shape: ExtensionRecord(BoxObstacle(origin: position, dimensions: .init(width: dimension, depth: dimension, height: dimension))))
}
@Test func objectSeatMovementPreservesSeparateIdentitiesAndScenarioScope() throws {
    var project = try objectEditorFixture()
    var candidate = project.scenarios[0]; candidate.id = UUID(); candidate.name = "Candidate"
    project.scenarios.append(candidate)
    let seat = project.scenarios[0].inputs.usage.seats[0], scenarioID = project.scenarios[0].id
    let selection = RoomPlanSelection(kind: .seat, objectID: seat.id)
    try ObjectEditing.move(selection, to: .init(x: 3.5, y: 2.5, z: 0.8), scenarioID: scenarioID, project: &project)
    let updated = project.scenarios[0].inputs.usage.seats[0]
    #expect(updated.id == seat.id)
    #expect(updated.samples[0].id == seat.samples[0].id)
    #expect(abs(updated.samples[0].position.z - 1.2) < 1e-12)
    #expect(updated.samples[0].position.x == 3.5 && updated.samples[0].position.y == 2.5)
    #expect(project.scenarios[1].inputs.usage.seats[0] == seat)
    #expect(project.scenarios[0].inputs.usage.occupants[0].seatID == seat.id)
}
@Test func objectDeviceMovementTranslatesPortsAndLeavesSensorFixed() throws {
    var project = try objectEditorFixture()
    let device = project.scenarios[0].inputs.hvac[0], sensor = project.scenarios[0].inputs.controls[0].sensorPosition
    try ObjectEditing.move(.init(kind: .hvac, objectID: device.id), to: .init(x: 0.5, y: 2, z: 2.5), scenarioID: project.scenarios[0].id, project: &project)
    let updated = project.scenarios[0].inputs.hvac[0]
    #expect(updated.ports.map(\.id) == device.ports.map(\.id))
    #expect(updated.ports[1].position.x == 0.5 && updated.ports[1].position.y == 2.5)
    #expect(project.scenarios[0].inputs.controls[0].sensorPosition == sensor)
    #expect(updated.ports[0].direction == device.ports[0].direction)
}
@Test func objectInvalidEditsAreAtomicAndSharedFurnitureChecksAllScenarios() throws {
    var project = try objectEditorFixture()
    var alternate = project.scenarios[0]; alternate.id = UUID()
    alternate.inputs.usage.seats[0].position = .init(x: 5, y: 3.5, z: 0.1)
    alternate.inputs.usage.seats[0].samples[0].position = .init(x: 5, y: 3.5, z: 0.2)
    project.scenarios.append(alternate)
    let before = project
    let box = try editorBox(roomID: project.geometry.rooms[0].id, position: .init(x: 4.9, y: 3.4, z: 0))
    #expect(throws: (any Error).self) { try ObjectEditing.upsertFurniture(box, project: &project) }
    #expect(project == before)
    let outside = try editorBox(roomID: project.geometry.rooms[0].id, position: .init(x: 5.9, y: 1, z: 0))
    #expect(throws: (any Error).self) { try ObjectEditing.upsertFurniture(outside, project: &project) }
    #expect(project == before)
    let overlap = try editorBox(roomID: project.geometry.rooms[0].id, position: .init(x: 1.1, y: 1.1, z: 0))
    #expect(throws: (any Error).self) { try ObjectEditing.upsertFurniture(overlap, project: &project) }
    #expect(project == before)
}
@Test func objectSampleMustRemainInFluidDomainAndIDsStayStable() throws {
    var project = try objectEditorFixture()
    let sample = project.scenarios[0].inputs.usage.seats[0].samples[0], before = project
    let selection = RoomPlanSelection(kind: .sample, objectID: sample.id), scenarioID = project.scenarios[0].id
    #expect(throws: (any Error).self) { try ObjectEditing.move(selection, to: .init(x: 1.2, y: 1.2, z: 0.5), scenarioID: scenarioID, project: &project) }
    #expect(project == before)
    #expect(throws: (any Error).self) { try ObjectEditing.move(selection, to: .init(x: 0, y: 2, z: 1), scenarioID: scenarioID, project: &project) }
    try ObjectEditing.move(selection, to: .init(x: 3, y: 2, z: 1.4), scenarioID: scenarioID, project: &project)
    #expect(project.scenarios[0].inputs.usage.seats[0].samples[0].id == sample.id)
    #expect(project.scenarios[0].inputs.usage.seats[0].position == before.scenarios[0].inputs.usage.seats[0].position)
}
@Test func objectDeletionMaintainsRelatedReferencesWithoutTouchingOtherScenario() throws {
    var project = try objectEditorFixture()
    var alternate = project.scenarios[0]; alternate.id = UUID(); project.scenarios.append(alternate)
    let scenarioID = project.scenarios[0].id
    try ObjectEditing.delete(.init(kind: .seat, objectID: project.scenarios[0].inputs.usage.seats[0].id), scenarioID: scenarioID, project: &project)
    #expect(project.scenarios[0].inputs.usage.seats.isEmpty && project.scenarios[0].inputs.usage.occupants.isEmpty)
    #expect(project.scenarios[1] == alternate)
    try ObjectEditing.delete(.init(kind: .hvac, objectID: project.scenarios[0].inputs.hvac[0].id), scenarioID: scenarioID, project: &project)
    #expect(project.scenarios[0].inputs.hvac.isEmpty && project.scenarios[0].inputs.controls.isEmpty)
    #expect(try ProjectValidator().validate(project, registry: .builtIn).passes(.projectIntegrity))
}
@Test func objectUnknownExtensionIsPreservedAndCannotBeReinterpreted() throws {
    var project = try objectEditorFixture()
    let payload = try JSONValue(data: Data("{\"opaque\":123456789012345678901234567890,\"nested\":[null,true]}".utf8))
    let id = project.scenarios[0].inputs.hvac[0].id
    project.scenarios[0].inputs.hvac[0].definition = .init(kind: "future.hvac", payloadVersion: 8, payload: payload)
    let before = project
    #expect(throws: (any Error).self) { try ObjectEditing.move(.init(kind: .hvac, objectID: id), to: .init(x: 1, y: 2, z: 2), scenarioID: project.scenarios[0].id, project: &project) }
    #expect(project == before)
    try ObjectEditing.move(.init(kind: .seat, objectID: project.scenarios[0].inputs.usage.seats[0].id), to: .init(x: 3.5, y: 2, z: 0.7), scenarioID: project.scenarios[0].id, project: &project)
    #expect(project.scenarios[0].inputs.hvac[0].definition.payload == payload)
}
@Test func objectImportedProjectAllowsIncrementalRepairAndRejectsNewIssue() throws {
    var project = try objectEditorFixture()
    let scenarioID = project.scenarios[0].id, seatID = project.scenarios[0].inputs.usage.seats[0].id
    project.scenarios[0].inputs.usage.seats[0].position.x = 10
    project.scenarios[0].inputs.usage.seats[0].samples[0].position.x = 10
    project.scenarios[0].inputs.usage.equipment[0].position.y = 10
    try ObjectEditing.move(.init(kind: .seat, objectID: seatID), to: .init(x: 3, y: 2, z: 0.7), scenarioID: scenarioID, project: &project)
    let issues = try ProjectValidator().validate(project, registry: .builtIn).issues.filter { $0.blocks.contains(.projectIntegrity) }
    #expect(issues.count == 1 && issues[0].path.contains("equipment"))
    let before = project
    #expect(throws: (any Error).self) { try ObjectEditing.move(.init(kind: .sample, objectID: project.scenarios[0].inputs.usage.seats[0].samples[0].id), to: .init(x: 0, y: 2, z: 1), scenarioID: scenarioID, project: &project) }
    #expect(project == before)
    try ObjectEditing.move(.init(kind: .equipment, objectID: project.scenarios[0].inputs.usage.equipment[0].id), to: .init(x: 4, y: 3, z: 1), scenarioID: scenarioID, project: &project)
    #expect(try ProjectValidator().validate(project, registry: .builtIn).passes(.projectIntegrity))
}
@Test func objectImportedIssueMultiplicityCannotGrow() throws {
    var project = try objectEditorFixture()
    // Intervals have no UUID. Both errors infer the same occupant identity and normalized path.
    let fraction = Ratio.known(value: 1, source: .init(kind: .user))
    project.scenarios[0].inputs.usage.occupants[0].schedule.intervals = [.init(startMinute: 0, endMinute: 2000, fraction: fraction)]
    let before = project
    let oldIssues = try ProjectValidator().validate(project, registry: .builtIn).issues.filter { $0.blocks.contains(.projectIntegrity) }
    #expect(oldIssues.count == 1 && oldIssues[0].code == "schedule_interval")
    #expect(throws: (any Error).self) {
        try ObjectEditing.transaction(&project) { candidate in
            candidate.scenarios[0].inputs.usage.occupants[0].schedule.intervals.append(.init(startMinute: 2000, endMinute: 2100, fraction: fraction))
        }
    }
    #expect(project == before)
}
@Test func objectDraftUnchangedValuesPreserveSourcesAndPortDirection() throws {
    let project = try objectEditorFixture(), input = project.scenarios[0].inputs
    let device = input.hvac[0], split = try device.definition.resolved(as: SingleSplit.self, registry: .builtIn)!
    let draft = DeviceEditDraft(device, split: split, control: input.controls[0], initialSensor: .init(x: 1, y: 1, z: 1))
    #expect(try draft.value() == device)
    #expect(try draft.control.value(deviceID: device.id) == input.controls[0])
    let seat = input.usage.seats[0], seatDraft = SeatEditDraft(seat, occupant: input.usage.occupants[0])
    #expect(try seatDraft.value() == seat)
    #expect(try seatDraft.occupant.value(seatID: seat.id) == input.usage.occupants[0])
    var port = draft.ports[0]
    port.flow.enterValue("0.3")
    try port.deriveSpeed()
    let speed: Speed = try port.speed.parameter(as: SpeedTag.self)
    #expect(abs(speed.value! - 3) < 1e-12)
    if case .known(_, let source, _) = speed { #expect(source.kind == .assumed && source.note?.contains("推导") == true) }
}

@Test func objectRepairCannotTransferIssueBetweenScenariosWithSharedEntityIDs() throws {
    var project = try objectEditorFixture()
    var alternate = project.scenarios[0]; alternate.id = UUID(); project.scenarios.append(alternate)
    project.scenarios[0].inputs.usage.seats[0].samples[0].position.x = 0
    let before = project
    #expect(throws: (any Error).self) {
        try ObjectEditing.transaction(&project) { candidate in
            candidate.scenarios[0].inputs.usage.seats[0].samples[0].position.x = 3
            candidate.scenarios[1].inputs.usage.seats[0].samples[0].position.x = 0
        }
    }
    #expect(project == before)
}

@Test func objectReferenceRepairsPreserveOccupantAndControlIdentities() throws {
    var project = try objectEditorFixture()
    let scenarioID = project.scenarios[0].id
    let occupantID = project.scenarios[0].inputs.usage.occupants[0].id
    let controlID = project.scenarios[0].inputs.controls[0].id
    project.scenarios[0].inputs.usage.occupants[0].seatID = UUID()
    project.scenarios[0].inputs.controls[0].deviceID = UUID()
    var occupant = project.scenarios[0].inputs.usage.occupants[0]
    occupant.seatID = project.scenarios[0].inputs.usage.seats[0].id
    try ObjectEditing.upsertOccupant(occupant, scenarioID: scenarioID, project: &project)
    #expect(project.scenarios[0].inputs.usage.occupants[0].id == occupantID)
    var control = project.scenarios[0].inputs.controls[0]
    control.deviceID = project.scenarios[0].inputs.hvac[0].id
    try ObjectEditing.upsertControl(control, scenarioID: scenarioID, project: &project)
    #expect(project.scenarios[0].inputs.controls[0].id == controlID)
    #expect(try ProjectValidator().validate(project, registry: .builtIn).passes(.projectIntegrity))
}

@Test func objectNoopFurnitureMovePreservesOriginalRecordTokens() throws {
    var project = try objectEditorFixture(), before = project
    let furniture = project.geometry.obstacles[0]
    let box = try furniture.shape.resolved(as: BoxObstacle.self, registry: .builtIn)!
    try ObjectEditing.move(.init(kind: .furniture, objectID: furniture.id), to: box.origin, scenarioID: project.scenarios[0].id, project: &project)
    #expect(project == before)
}

@Test func objectStaleDraftRejectsChangedProjectWhileAcceptingOriginalBase() throws {
    let base = try objectEditorFixture()
    try ObjectEditing.requireCurrentProject(base: base, current: base)
    var changed = base
    changed.scenarios[0].inputs.usage.seats[0].position.x += 0.2
    #expect(throws: (any Error).self) { try ObjectEditing.requireCurrentProject(base: base, current: changed) }
    var otherScenario = base
    var alternate = base.scenarios[0]; alternate.id = UUID(); otherScenario.scenarios.append(alternate)
    #expect(throws: (any Error).self) { try ObjectEditing.requireCurrentProject(base: base, current: otherScenario) }
}
