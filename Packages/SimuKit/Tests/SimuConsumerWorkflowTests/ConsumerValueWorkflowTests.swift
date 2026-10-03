import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

@Test func homeTemplateCanPrepareRulesWithoutThermalInputs() throws {
    let template = try ProjectTemplateFactory.make(kind: .home, options: .defaults(for: .home))
    let project = template.project
    #expect(project.spaceType == .home)
    #expect(project.scenarios[0].inputs.usage.occupants.isEmpty)
    #expect(try ProjectValidator().validate(project, registry: .builtIn).passes(.projectIntegrity))
    let request = try AnalysisInputResolver().request(project: project, scenarioID: project.scenarios[0].id,
        method: .init(kind: .airflowPreview), configuration: .init(payload: .airflowPreview(.init()), acceptedAssumptions: [.genericCone]))
    #expect(request.method.resultBasis == .rulePreview)
}

@Test func captureConversionKeepsSourceAndDoesNotInventEquipment() throws {
    let capture = RoomCaptureSnapshot(appleOriginInDomain: .init(x: -1, y: -2, z: -3), roomDimensionsMeters: .init(x: 5, y: 4, z: 3),
        furniture: [.init(origin: .init(x: 1, y: 1, z: 0), dimensions: .init(x: 1, y: 1, z: 0.8))], source: .init(kind: .scan, reference: "synthetic capture"))
    let project = try RoomCaptureConversion.project(capture)
    #expect(project.scenarios[0].inputs.hvac.isEmpty)
    #expect(project.scenarios[0].inputs.usage.seats.isEmpty)
    #expect(project.geometry.rooms[0].northAngle.value == nil)
    let room = try #require(try project.geometry.rooms[0].shape.resolved(as: RectangularRoom.self, registry: .builtIn))
    if case .known(_, let source, _) = room.dimensions.width { #expect(source.kind == .scan) }
    else { Issue.record("Scan dimension lost its source") }
    #expect(project.geometry.obstacles.count == 1)
    let outside = RoomCaptureSnapshot(appleOriginInDomain: capture.appleOriginInDomain, roomDimensionsMeters: capture.roomDimensionsMeters,
        furniture: [.init(origin: .init(x: 9, y: 1, z: 0), dimensions: .init(x: 1, y: 1, z: 1))], source: capture.source)
    #expect(throws: (any Error).self) { try RoomCaptureConversion.project(outside) }
}

@Test func copiedCandidateKeepsSharedGeometryAndIndependentScenarioIdentity() throws {
    let project = try ProjectTemplateFactory.make(kind: .home, options: .defaults(for: .home)).project
    let candidate = try ScenarioEditing.copy(project, scenarioID: project.scenarios[0].id, name: "候选")
    #expect(candidate.scenarios[0].id != candidate.scenarios[1].id)
    #expect(candidate.scenarios[0].inputs == candidate.scenarios[1].inputs)
    #expect(candidate.geometry == project.geometry)
}
