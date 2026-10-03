import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuVisualization
@testable import SimuWorkspace

@Test @MainActor func copyUsesDeclaredSourceConfigurationAndUnifiedUndo() throws {
    let original = try ProjectTemplateFactory.make(kind: .home, options: .defaults(for: .home)).project
    let project = try ScenarioEditing.copy(original, scenarioID: original.scenarios[0].id, name: "已调整档案")
    var configuration = AnalysisConfigurationStore(projectID: project.id)
    configuration.set(.init(payload: .airflowPreview(.init(pathCount: 16)), acceptedAssumptions: [.genericCone]), scenarioID: project.scenarios[0].id)
    let sourceConfig = AnalysisConfiguration(payload: .airflowPreview(.init(pathCount: 64)), acceptedAssumptions: [.genericCone])
    configuration.set(sourceConfig, scenarioID: project.scenarios[1].id)
    let store = WorkspaceStore(); store.load(project, analysisConfiguration: configuration)
    let edited = try ScenarioEditing.copy(project, scenarioID: project.scenarios[1].id, name: "新候选")
    try store.replaceProject(edited, actionName: "复制方案", copiedFromScenarioID: project.scenarios[1].id)
    #expect(store.analysisConfiguration?.configuration(scenarioID: edited.scenarios[2].id, kind: .airflowPreview) == sourceConfig)
    store.undo()
    #expect(store.project == project && store.analysisConfiguration == configuration)
    store.redo()
    #expect(store.project == edited)
    #expect(store.analysisConfiguration?.configuration(scenarioID: edited.scenarios[2].id, kind: .airflowPreview) == sourceConfig)
}

@Test func comparisonReopensWithParentsAndRejectsAlteredParent() async throws {
    let original = try ProjectTemplateFactory.make(kind: .home, options: .defaults(for: .home)).project
    let project = try ScenarioEditing.copy(original, scenarioID: original.scenarios[0].id, name: "候选")
    var document = try SimuNowDocument(project: project, preservedEntries: ["opaque": .file(Data([0, 255, 1]))])
    let instance = document.documentInstanceID
    var evidence: [FixedEstimateEvidence] = []
    for scenario in project.scenarios {
        let request = try AnalysisInputResolver().request(project: project, scenarioID: scenario.id, method: .init(kind: .airflowPreview),
            configuration: .init(payload: .airflowPreview(.init()), acceptedAssumptions: [.genericCone]))
        let execution = try await AirflowPreviewExecutor().execute(request, progress: { _ in })
        let result = LocalAnalysisResult(identity: request.identity, method: request.method, checks: execution.checks,
            assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: execution.payload)
        let artifact = try NativeArtifactCodec().make(request: request, result: result)
        document = try document.appendingNativeAnalysis(artifact, expectedProjectID: project.id)
        evidence.append(.init(request: request, result: result, currentInputHash: request.identity.inputHash))
    }
    let snapshot = try ComparisonRecordCodec.snapshotFor(evidence, decisions: ["direction"])
    let artifact = try FixedComparisonArtifacts.make(snapshot, entries: document.preservedEntries)
    document = try document.appendingComparison(artifact)
    #expect(document.documentInstanceID == instance)
    #expect(document.preservedEntries["opaque"] == .file(Data([0, 255, 1])))
    let reopened = try SimuNowDocument(package: document.makeFileWrapper())
    #expect(reopened.documentInstanceID != instance)
    #expect(try FixedComparisonArtifacts.load(artifact.data, entries: reopened.preservedEntries, projectID: project.id).record == artifact.record)
    var damaged = reopened.preservedEntries
    try damaged.setNativeEntry(.file(Data("{}".utf8)), at: ["runs", evidence[0].result.identity.runID.uuidString.lowercased(), "native-analysis", "result.json"], allowReplace: true)
    #expect(throws: (any Error).self) { try FixedComparisonArtifacts.load(artifact.data, entries: damaged, projectID: project.id) }
}

@Test func measurementAppendIsIdempotentPreservesOpaqueAndRejectsIdentityCollision() throws {
    let project = try ProjectTemplateFactory.make(kind: .home, options: .defaults(for: .home)).project
    let document = try SimuNowDocument(project: project, preservedEntries: ["future": .file(Data([3, 2, 1]))])
    let dataset = MeasurementDataset(projectID: project.id, sourceSHA256: String(repeating: "a", count: 64), records: [], issues: [])
    let artifact = try MeasurementArtifact.make(dataset)
    let saved = try document.appendingMeasurements(artifact)
    #expect(try saved.appendingMeasurements(artifact).preservedEntries == saved.preservedEntries)
    #expect(saved.preservedEntries["future"] == document.preservedEntries["future"])
    let collision = try MeasurementArtifact.make(.init(id: dataset.id, projectID: project.id, sourceSHA256: String(repeating: "b", count: 64), records: [], issues: []))
    #expect(throws: (any Error).self) { try saved.appendingMeasurements(collision) }
    #expect(try MeasurementArtifact.load(id: dataset.id, entries: saved.preservedEntries, projectID: project.id).dataset == dataset)
}

@Test func comparisonCameraRoundTripsAndRejectsMalformedValues() throws {
    let camera = RoomCameraState(target: .init(x: 1, y: 2, z: 3), distance: 4, yawDegrees: 90, pitchDegrees: 30)
    let encoder = JSONEncoder()
    #expect(try JSONDecoder().decode(RoomCameraState.self, from: encoder.encode(camera)) == camera)
    var value = try #require(JSONSerialization.jsonObject(with: encoder.encode(camera)) as? [String: Any])
    value["distance"] = -1
    #expect(throws: (any Error).self) { try JSONDecoder().decode(RoomCameraState.self, from: JSONSerialization.data(withJSONObject: value)) }
}
