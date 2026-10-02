import Foundation
import Testing
import SimuCore
import SimuWorkspace

private func scenarioProject() throws -> ProjectDocument {
    try ProjectTemplateFactory.make(kind: .office, options: .defaults(for: .office)).project
}

@Test func copiedScenarioHasIndependentInputsAndStableNestedIdentities() throws {
    let project = try scenarioProject()
    let baselineID = project.scenarios[0].id
    var edited = try ScenarioEditing.copy(project, scenarioID: baselineID, name: "候选 A")
    #expect(edited.scenarios.count == 2)
    #expect(edited.scenarios[1].id != baselineID)
    #expect(edited.scenarios[1].inputs == project.scenarios[0].inputs)
    #expect(edited.scenarios[1].evaluation == project.scenarios[0].evaluation)
    edited.scenarios[1].inputs.usage.seats[0].name = "候选座位"
    edited.scenarios[1].inputs.controls[0].setpoint = .known(value: 25, source: .init(kind: .user))
    #expect(edited.scenarios[0] == project.scenarios[0])
    #expect(edited.scenarios[1].inputs.usage.seats[0].id == project.scenarios[0].inputs.usage.seats[0].id)
    #expect(try ProjectValidator().validate(edited, registry: .builtIn).passes(.projectIntegrity))
    let renamed = try ScenarioEditing.rename(edited, scenarioID: baselineID, name: " 新基准名称 ")
    #expect(renamed.scenarios[0].id == baselineID && renamed.scenarios[0].name == "新基准名称")
    #expect(throws: ScenarioEditingError.invalidName) { try ScenarioEditing.rename(project, scenarioID: baselineID, name: "  ") }
    #expect(throws: (any Error).self) { try ScenarioEditing.copy(project, scenarioID: UUID(), name: "missing") }
}

@Test func deletingBaselineRequiresExplicitExistingReplacement() throws {
    let project = try scenarioProject()
    let baselineID = project.scenarios[0].id
    let two = try ScenarioEditing.copy(project, scenarioID: baselineID, name: "候选")
    let candidateID = two.scenarios[1].id
    #expect(throws: ScenarioEditingError.replacementRequired) {
        try ScenarioEditing.delete(two, scenarioID: baselineID, baselineScenarioID: baselineID)
    }
    #expect(throws: ScenarioEditingError.invalidBaseline) {
        try ScenarioEditing.delete(two, scenarioID: baselineID, baselineScenarioID: baselineID, replacementBaselineID: baselineID)
    }
    #expect(throws: ScenarioEditingError.invalidBaseline) {
        try ScenarioEditing.delete(two, scenarioID: baselineID, baselineScenarioID: baselineID, replacementBaselineID: UUID())
    }
    let removed = try ScenarioEditing.delete(two, scenarioID: baselineID, baselineScenarioID: baselineID, replacementBaselineID: candidateID)
    #expect(removed.project.scenarios.map(\.id) == [candidateID])
    #expect(removed.baselineScenarioID == candidateID)
    let removeCandidate = try ScenarioEditing.delete(two, scenarioID: candidateID, baselineScenarioID: baselineID)
    #expect(removeCandidate.baselineScenarioID == baselineID)
    #expect(removeCandidate.project.geometry == two.geometry)
}

@Test func editCheckpointsAndSnapshotsPreserveUnknownPayloadAndAreImmutable() throws {
    var project = try scenarioProject()
    let unknown = try JSONValue(data: Data("{\"number\":123456789012345678901234567890,\"nested\":[null,true,1.2345678901234567890123456789]}".utf8))
    project.scenarios[0].inputs.hvac[0].definition = .init(kind: "future.hvac", payloadVersion: 19, payload: unknown)
    let id = project.scenarios[0].id
    let checkpoint = try ProjectEditCheckpoint.capture(project, baselineScenarioID: id)
    let snapshot = try ScenarioEditing.snapshot(project, scenarioID: id)
    #expect(snapshot.validation.passes(.projectIntegrity))
    #expect(!snapshot.validation.passes(.inputPreparation))
    #expect(snapshot.validation.issues.contains { $0.code == "unsupported_type" })
    let copied = try ScenarioEditing.copy(project, scenarioID: id, name: "未知设备候选")
    #expect(copied.scenarios[1].inputs.hvac[0].definition.payload == unknown)
    project.geometry.rooms.removeAll()
    project.scenarios.removeAll()
    #expect(checkpoint.project.geometry.rooms.count == 1)
    #expect(checkpoint.baselineScenarioID == id)
    #expect(snapshot.input.geometry.rooms.count == 1)
    #expect(snapshot.input.inputs.hvac[0].definition.payload == unknown)
    let codec = ProjectCodec(registry: .builtIn)
    #expect(try codec.decode(codec.encode(checkpoint.project)) == checkpoint.project)
    #expect(try codec.decodeSnapshot(codec.encodeSnapshot(snapshot.input)) == snapshot.input)
}

@Test func snapshotPreparationIsScopedToSelectedScenarioAndMapsIssuePaths() throws {
    let project = try scenarioProject()
    var edited = try ScenarioEditing.copy(project, scenarioID: project.scenarios[0].id, name: "候选")
    edited.scenarios[0].inputs.usage.seats[0].samples.removeAll()
    let snapshot = try ScenarioEditing.snapshot(edited, scenarioID: edited.scenarios[1].id)
    #expect(!snapshot.validation.issues.contains { $0.code == "sample_required" })
    #expect(snapshot.validation.issues.contains { $0.path.hasPrefix("/scenarios/1/") })
    #expect(!snapshot.validation.issues.contains { $0.path.hasPrefix("/scenarios/0/") })
    #expect(snapshot.input.scenarioID == edited.scenarios[1].id)
}

@Test func invalidGeometryCannotEnterSafeSnapshotOrEditCheckpoint() throws {
    var project = try scenarioProject()
    project.scenarios[0].inputs.usage.seats[0].samples[0].position.x = -1
    #expect(throws: (any Error).self) { try ScenarioEditing.snapshot(project, scenarioID: project.scenarios[0].id) }
    #expect(throws: (any Error).self) { try ProjectEditCheckpoint.capture(project) }
    let valid = try scenarioProject()
    #expect(throws: ScenarioEditingError.invalidBaseline) { try ProjectEditCheckpoint.capture(valid, baselineScenarioID: UUID()) }
}
