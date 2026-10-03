import Foundation
import SimuCore
import SimuSimulation
import SimuVisualization
import SimuWorkspace
import Testing

#if canImport(RealityKit)
    import RealityKit
#endif
#if canImport(Darwin)
    import Darwin
#endif

private func n3Project(obstruction: Bool = false) throws -> ProjectDocument {
    var project = try N3TestFixture.make()
    project.scenarios = Array(project.scenarios.prefix(1))
    project.geometry.obstacles = try N3TestFixture.obstacles(enabled: obstruction)
    return project
}
private func n3Config(
    paths: Int = 32, segments: Int = 128, seed: UInt32 = 1, length: Double? = nil, radius: Double = 0.05,
    angle: Double = 12
) -> AnalysisConfiguration {
    .init(
        payload: .airflowPreview(
            .init(
                baseRadiusMeters: radius, halfAngleDegrees: angle, lengthMeters: length, pathCount: paths,
                maximumSegments: segments, seed: seed)), acceptedAssumptions: [.genericCone])
}
private func n3Request(
    _ project: ProjectDocument? = nil, config: AnalysisConfiguration = n3Config(), id: UUID = UUID()
) throws -> LocalAnalysisRequest {
    let project = try project ?? n3Project()
    return try AnalysisInputResolver().request(
        project: project, scenarioID: project.scenarios[0].id, method: .init(kind: .airflowPreview),
        configuration: config, runID: id)
}
private func n3Input(_ project: ProjectDocument? = nil, config: AnalysisConfiguration = n3Config()) throws
    -> AirflowPreviewInput
{ try .init(request: n3Request(project, config: config)) }
private func n3Execution(_ request: LocalAnalysisRequest) async throws -> LocalAnalysisExecution {
    try await AirflowPreviewExecutor().execute(request) { _ in }
}
private func n3Result(_ request: LocalAnalysisRequest) async throws -> LocalAnalysisResult {
    let execution = try await n3Execution(request)
    return .init(
        identity: request.identity, method: request.method, checks: execution.checks,
        assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: execution.payload)
}
@Test func n3CenterEdgeBehindFormula() throws {
    let input = try n3Input()
    let field = input.field
    let o = field.origin
    let s = 2.0
    let center = Position3D(x: o.x + s, y: o.y, z: o.z)
    let sample = try #require(field.sample(at: center))
    #expect(sample.direction == field.axis)
    #expect(abs(sample.pathStrength - 1 / pow(1 + s / field.profile.lengthMeters, 2)) < 1e-12)
    let edge = Position3D(
        x: center.x, y: center.y + field.profile.configuration.baseRadiusMeters + field.profile.slope * s,
        z: center.z)
    #expect(abs(try #require(field.sample(at: edge)).pathStrength) < 1e-9)
    #expect(field.sample(at: .init(x: o.x - 1, y: o.y, z: o.z)) == nil)
    #expect(field.sample(at: .init(x: 100, y: 2, z: 1.5)) == nil)
}
@Test func n3PureFieldRigidEquivariance() throws {
    let original = try n3Input().field
    func transform(_ p: Position3D) -> Position3D { .init(x: -p.y + 10, y: p.x - 2, z: p.z + 4) }
    let rotated = try RuleDirectionField(
        origin: transform(original.origin), direction: .init(x: 0, y: 1, z: 0), profile: original.profile)
    let p = Position3D(x: 2, y: 2.1, z: 1.55)
    let a = try #require(original.sample(at: p))
    let b = try #require(rotated.sample(at: transform(p)))
    #expect(abs(a.pathStrength - b.pathStrength) < 1e-9)
    #expect(abs(b.direction.x + a.direction.y) < 1e-9)
    #expect(abs(b.direction.y - a.direction.x) < 1e-9)
    #expect(abs(b.direction.z - a.direction.z) < 1e-9)
}
@Test func n3UnsupportedZeroNonunitMultipleAndMissingSource() throws {
    var p = try n3Project()
    let supply = p.scenarios[0].inputs.hvac[0].ports[0]
    for direction in [Direction3D(x: 0, y: 0, z: 0), .init(x: 2, y: 0, z: 0)] {
        p.scenarios[0].inputs.hvac[0].ports[0].direction = direction
        #expect(throws: (any Error).self) { try n3Request(p) }
    }
    p.scenarios[0].inputs.hvac[0].ports = [supply]
    p.scenarios[0].inputs.hvac.append(p.scenarios[0].inputs.hvac[0])
    #expect(throws: (any Error).self) { try n3Request(p) }
    p.scenarios[0].inputs.hvac.removeLast()
    p.scenarios[0].inputs.hvac[0].ports = []
    #expect(throws: (any Error).self) { try n3Request(p) }
    p = try n3Project(obstruction: true)
    p.geometry.obstacles[0].shape = .init(
        kind: "future.mesh", payloadVersion: 1, payload: .object(["vertices": .array([])]))
    #expect(throws: (any Error).self) { try n3Request(p) }
}
@Test func n3ProfileVersionsNumbersAndHashDensity() throws {
    let input = try n3Input()
    #expect(throws: (any Error).self) {
        try PreviewProfile(configuration: .init(profileVersion: 2), room: input.room)
    }
    #expect(throws: (any Error).self) {
        try PreviewProfile(configuration: .init(lengthMeters: 100), room: input.room)
    }
    #expect(throws: (any Error).self) { try n3Input(config: n3Config(radius: 0)) }
    #expect(throws: (any Error).self) { try n3Input(config: n3Config(angle: 46)) }
    let first = try n3Request(config: n3Config(paths: 16))
    let second = try n3Request(config: n3Config(paths: 64))
    let changedSeed = try n3Request(config: n3Config(seed: .max))
    #expect(first.identity.inputHash != second.identity.inputHash)
    #expect(first.identity.inputHash != changedSeed.identity.inputHash)
    #expect(
        try AirflowTargetAssessment.assess(AirflowPreviewInput(request: first))
            == AirflowTargetAssessment.assess(AirflowPreviewInput(request: second)))
}
@Test func n3HaltonGoldenMaximumSeedAndDeterminism() throws {
    #expect(PreviewSampling.halton(index: 2, base: 2) == 0.25)
    #expect(abs(PreviewSampling.halton(index: 2, base: 3) - 2.0 / 3) < 1e-15)
    let input = try n3Input()
    let first = try PreviewPathTracer.trace(input)
    let second = try PreviewPathTracer.trace(input)
    #expect(first.paths == second.paths)
    #expect(first.paths[0].id == 0)
    #expect(first.paths[0].points[0].position == input.field.origin)
    let last = try PreviewPathTracer.trace(n3Input(config: n3Config(seed: .max)))
    #expect(last.paths.count <= 32)
    #expect(last.paths[0] == first.paths[0])
    #expect(last.paths[1].points[0] != first.paths[1].points[0])
}
@Test func n3ThinObstacleNoTunnellingAtAnyStepBudget() throws {
    let project = try n3Project(obstruction: true)
    for segments in [1, 4, 16, 128] {
        let paths = try PreviewPathTracer.trace(n3Input(project, config: n3Config(segments: segments))).paths
        let center = try #require(paths.first { $0.id == 0 })
        #expect(center.termination == .hit)
        #expect(center.hitEntityID == N3TestFixture.id(70))
        #expect(abs(center.points.last!.position.x - 3) < 1e-9)
        #expect(
            paths.flatMap(\.points).allSatisfy {
                $0.position.x <= 3 + 1e-9 || $0.position.y < 1.5 || $0.position.y > 2.5 || $0.position.z > 2
            })
    }
}
@Test func n3ClosedSlabsParallelCornerTangentAndStableTie() throws {
    let b = GeometryBounds(origin: .init(x: 1, y: 1, z: 1), size: .init(x: 1, y: 1, z: 1))
    let small = N3TestFixture.id(70)
    let large = N3TestFixture.id(71)
    #expect(
        SegmentIntersection.slab(
            from: .init(x: 0, y: 1, z: 1), to: .init(x: 3, y: 1, z: 1), bounds: b, tolerance: 1e-10)?.enter
            == 1.0 / 3)
    #expect(
        SegmentIntersection.slab(
            from: .init(x: 0, y: 0.5, z: 1), to: .init(x: 3, y: 0.5, z: 1), bounds: b, tolerance: 1e-10)
            == nil)
    #expect(
        SegmentIntersection.slab(
            from: .init(x: 0, y: 0, z: 0), to: .init(x: 1, y: 1, z: 1), bounds: b, tolerance: 1e-10)?.enter
            == 1)
    #expect(
        SegmentIntersection.slab(
            from: .init(x: 1, y: 1, z: 1), to: .init(x: 0, y: 0, z: 0), bounds: b, tolerance: 1e-10)?.enter
            == 0)
    let boxes = [PreviewObstacle(id: large, bounds: b), .init(id: small, bounds: b)]
    #expect(
        SegmentIntersection.firstObstacle(
            from: .init(x: 0, y: 1, z: 1), to: .init(x: 3, y: 1, z: 1), obstacles: boxes, tolerance: 1e-10)?
            .obstacleID == small)
}
@Test func n3WallSourceOffsetInternalSourceAndThinOffsetObstacle() throws {
    var p = try n3Project()
    p.scenarios[0].inputs.hvac[0].ports[0].position.x = 0
    let wall = try n3Input(p)
    let path = try #require(PreviewPathTracer.trace(wall).paths.first)
    #expect(wall.isWallSource)
    #expect(abs(path.points[0].position.x - wall.field.profile.wallSourceOffsetMeters) < 1e-15)
    let internalInput = try n3Input()
    #expect(!internalInput.isWallSource)
    #expect(
        try PreviewPathTracer.trace(internalInput).paths[0].points[0].position == internalInput.field.origin)
    p.scenarios[0].inputs.hvac[0].ports[0].direction = .init(x: 0, y: 1, z: 0)
    #expect(throws: (any Error).self) { try n3Input(p) }
    p = try n3Project(obstruction: true)
    p.scenarios[0].inputs.hvac[0].ports[0].position = .init(x: 3, y: 2, z: 1.5)
    #expect(throws: (any Error).self) { try n3Input(p) }
}
@Test func n3ExactRoomBoundaryWeakBudgetAndRejections() throws {
    let length = 5.95
    let input = try n3Input(config: n3Config(paths: 1, segments: 1, length: length))
    let center = try #require(PreviewPathTracer.trace(input).paths.first)
    #expect(center.termination == .escaped)
    #expect(abs(center.points.last!.position.x - 6) < 1e-9)
    let weak = try n3Input(
        config: .init(
            payload: .airflowPreview(.init(minimumStrength: 1)), acceptedAssumptions: [.genericCone]))
    #expect(try PreviewPathTracer.trace(weak).paths[0].termination == .weak)
    var project = try n3Project()
    project.scenarios[0].inputs.hvac[0].ports[0].position = .init(x: 0, y: 0, z: 0)
    project.scenarios[0].inputs.hvac[0].ports[0].direction = .init(
        x: 1 / sqrt(3), y: 1 / sqrt(3), z: 1 / sqrt(3))
    let traced = try PreviewPathTracer.trace(n3Input(project))
    #expect(!traced.rejections.isEmpty)
    #expect(traced.paths.count + traced.rejections.count == 32)
    #expect(traced.rejections.allSatisfy { !$0.reason.isEmpty })
    #expect(traced.paths.allSatisfy { $0.points.count <= 129 })
}
@Test func n3CancellationDoesNotReturnPartialTrace() async throws {
    let input = try n3Input(config: n3Config(paths: 64))
    let task = Task.detached {
        try Task.checkCancellation()
        return try PreviewPathTracer.trace(input)
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Cancelled trace should not succeed")
    } catch is CancellationError {} catch { Issue.record("Unexpected cancellation error \(error)") }
}
@Test func n3GoldenTargetRelationsAndLineOfSightEvidence() throws {
    let clear = try AirflowTargetAssessment.assess(n3Input())
    let blocked = try AirflowTargetAssessment.assess(n3Input(n3Project(obstruction: true)))
    #expect(clear.map(\.state) == [.intersectsAssumedPath, .intersectsAssumedPath, .outsideAssumedPath])
    #expect(blocked.map(\.state) == [.intersectsAssumedPath, .occluded, .outsideAssumedPath])
    #expect(blocked[1].hitEntityID == N3TestFixture.id(70))
    #expect(abs(blocked[1].hitPosition!.x - 3) < 1e-9)
}
@Test func n3InvalidTargetsMixedSeatAndPositionMarkers() throws {
    var project = try n3Project(obstruction: true)
    let roomID = project.geometry.rooms[0].id
    project.scenarios[0].inputs.usage.seats = [
        .init(
            id: N3TestFixture.id(50), roomID: roomID, name: "mixed", position: .init(x: 2, y: 2, z: 1.5),
            samples: [
                .init(id: N3TestFixture.id(51), position: .init(x: 2, y: 2, z: 1.5)),
                .init(id: N3TestFixture.id(52), position: .init(x: 4, y: 2, z: 1.5)),
                .init(id: N3TestFixture.id(53), position: .init(x: 3.02, y: 2, z: 1.5)),
            ]),
        .init(
            id: N3TestFixture.id(54), roomID: roomID, name: "marker", position: .init(x: 2, y: 0.5, z: 1.5)),
    ]
    // The pure relation function documents invalid samples, while the production
    // readiness boundary separately rejects this damaged project below.
    let base = try n3Request(n3Project(obstruction: true))
    let snapshot = ScenarioInputSnapshot(
        projectID: project.id, scenarioID: project.scenarios[0].id,
        lengthUnit: project.lengthUnit, coordinateSystem: project.coordinateSystem,
        geometry: project.geometry, inputs: project.scenarios[0].inputs,
        evaluation: project.scenarios[0].evaluation)
    let raw = LocalAnalysisRequest(
        identity: base.identity, method: base.method,
        resolvedInput: .init(
            snapshot: snapshot, configuration: base.resolvedInput.configuration,
            adoptedAssumptions: base.resolvedInput.adoptedAssumptions), snapshotHash: base.snapshotHash,
        computationHash: base.computationHash, limits: base.limits)
    let relations = try AirflowTargetAssessment.assess(AirflowPreviewInput(request: raw))
    #expect(throws: (any Error).self) { _ = try n3Request(project) }
    #expect(
        relations.map(\.state) == [.intersectsAssumedPath, .occluded, .notEvaluated, .outsideAssumedPath])
    #expect(relations[2].missingReason != nil)
    #expect(relations[3].isPositionMarker)
    let payload = AirflowPreviewPayload(
        profileID: "simunow.preview.genericCone", profileVersion: 1, paths: [], relations: relations,
        validEmissionCount: 1)
    #expect(PreviewSeatAssessment.grouped(payload)[0].counts.isMixed)
}
@Test func n3PayloadStrictEvidenceAndRealSchemaExport() async throws {
    let request = try n3Request(n3Project(obstruction: true), id: N3TestFixture.id(900))
    let result = try await n3Result(request)
    let codec = NativeAnalysisCodec()
    #expect(try codec.decodeResult(codec.encodeResult(result)) == result)
    let data = try codec.encodeResult(result)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("m/s"))
    #expect(!text.contains("PMV"))
    #expect(text.contains("preview.occlusion.v1"))
    #expect(text.contains("sourcePortID"))
    #expect(text.contains("hitPosition"))
    if let dir = ProcessInfo.processInfo.environment["SIMUNOW_NATIVE_CONTRACT_DIR"] {
        try codec.encodeRequest(request).write(
            to: URL(fileURLWithPath: dir).appendingPathComponent("n3-production-request.json"))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("n3-production-result.json"))
    }
}
@Test func n3SingleOverlayBothProjectionsAndDisplayNoHashChange() async throws {
    let request = try n3Request(n3Project(obstruction: true))
    let result = try await n3Result(request)
    let overlay = try AirflowOverlayDescriptor(result: result)
    #expect(overlay.identity == result.identity)
    #expect(overlay.scene.paths[0].points.last!.x == 3)
    let bounds = try n3Input().room
    let projection = try #require(PlanProjection(bounds: bounds, screenWidth: 600, screenHeight: 400))
    let point = overlay.scene.paths[0].points.last!
    #expect(projection.unproject(projection.project(point), z: point.z) == point)
    #expect(CoordinateTransform.toDomain(CoordinateTransform.toApple(point)) == point)
}
@Test @MainActor func n3MergedMeshKeepsEntityBudgetAndNoTicker() async throws {
    if #available(macOS 15, iOS 18, *) {
        let request = try n3Request(config: n3Config(paths: 64))
        let result = try await n3Result(request)
        let project = request.resolvedInput.snapshot
        let scene = RoomSceneBuilder.build(
            project: .init(
                id: project.projectID, name: "test", spaceType: .office, geometry: project.geometry,
                scenarios: [
                    .init(
                        id: project.scenarioID, name: "test", inputs: project.inputs,
                        evaluation: project.evaluation)
                ]), scenarioID: project.scenarioID)
        let controller = RoomSceneController(bounds: scene.bounds)
        controller.reconcile(descriptor: scene, selection: nil, dark: false)
        let baseline = controller.statistics.entityCount
        controller.reconcile(
            descriptor: scene, overlay: try AirflowOverlayDescriptor(result: result).scene.preparedFor3D(),
            selection: nil, dark: false)
        #expect(controller.statistics.entityCount - baseline <= 64)
        #expect(controller.statistics.overlayPathCount == 64)
        #expect(controller.statistics.activeSubscriptions == 0)
        #expect(controller.overlayRenderingIssue == nil)
        controller.suspend()
        #expect(controller.statistics.entityCount == 1)
    }
}
private actor N3GateClock: PreviewDelayClock {
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    func waitForDebounce() async throws {
        try await withCheckedThrowingContinuation { continuations.append($0) }
        try Task.checkCancellation()
    }
    func release() {
        let c = continuations
        continuations = []
        for continuation in c { continuation.resume() }
    }
    func count() -> Int { continuations.count }
}
@Test @MainActor func n3TwentyEditsDebounceAndLatestIdentity() async throws {
    let gate = N3GateClock()
    let client = LocalAnalysisClient.production()
    let coordinator = PreviewCoordinator(client: client, clock: gate)
    var project = try n3Project()
    var input = PreviewWorkspaceInput(
        project: project, scenarioID: project.scenarios[0].id, configuration: n3Config())
    coordinator.setEnabled(true, input: input, registry: .builtIn, persist: { _ in })
    for index in 0..<20 {
        project.scenarios[0].inputs.hvac[0].ports[0].direction = try AirflowDirection.unit(
            yawDegrees: Double(index), pitchDegrees: 0)
        input = .init(project: project, scenarioID: project.scenarios[0].id, configuration: n3Config())
        coordinator.update(input, registry: .builtIn, persist: { _ in })
        await Task.yield()
    }
    for _ in 0..<200 where await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<10000 {
        if coordinator.analysis.stage == .completed { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let expected = try n3Request(project).identity.inputHash
    #expect(coordinator.currentResult?.identity.inputHash == expected)
    #expect(coordinator.analysis.records.count == 1)
    let run = coordinator.currentResult?.identity.runID
    coordinator.showPaths = false
    coordinator.showPaths = true
    #expect(coordinator.currentResult?.identity.runID == run)
    coordinator.stop()
    await client.shutdown()
}
@Test @MainActor func n3InputConfigurationUndoAndSharedGeometryStaleness() async throws {
    let store = WorkspaceStore(localAnalysisClient: LocalAnalysisClient.production())
    let project = try N3TestFixture.make()
    store.load(project)
    var configs = AnalysisConfigurationStore(projectID: project.id)
    for scenario in project.scenarios { configs.set(n3Config(), scenarioID: scenario.id) }
    try store.updateAnalysisConfiguration(configs)
    #expect(store.canUndo)
    store.undo()
    #expect(store.analysisConfiguration == nil)
    store.redo()
    #expect(store.analysisConfiguration == configs)
    var updated = project
    updated.geometry.obstacles = try N3TestFixture.obstacles(enabled: true)
    let originalHashes = try project.scenarios.map {
        try AnalysisInputResolver().request(
            project: project, scenarioID: $0.id, method: .init(kind: .airflowPreview),
            configuration: n3Config()
        ).identity.inputHash
    }
    let updatedHashes = try updated.scenarios.map {
        try AnalysisInputResolver().request(
            project: updated, scenarioID: $0.id, method: .init(kind: .airflowPreview),
            configuration: n3Config()
        ).identity.inputHash
    }
    #expect(zip(originalHashes, updatedHashes).allSatisfy { $0 != $1 })
}
@Test @MainActor func n3ResidentBoundAndLazySavedHistoryPreserveOpaque() async throws {
    let coordinator = AnalysisCoordinator(
        client: LocalAnalysisClient.unavailable, maximumResidentResults: 2, maximumResidentBytes: 1024 * 1024)
    var document = try SimuNowDocument(
        project: n3Project(),
        preservedEntries: ["future": .directory(["unknown.bin": .file(Data([0, 1, 255]))])])
    var artifacts: [NativeAnalysisArtifact] = []
    for index in 0..<4 {
        let request = try n3Request(document.project, id: N3TestFixture.id(10000 + index))
        let result = try await n3Result(request)
        let artifact = try NativeArtifactCodec().make(request: request, result: result)
        artifacts.append(artifact)
        document = try document.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    }
    coordinator.restore(artifacts)
    #expect(coordinator.results.count == 2)
    #expect(coordinator.records.count == 4)
    let index = NativeArtifactCodec().index(
        entries: document.preservedEntries, projectID: document.project.id)
    #expect(index.count == 4)
    #expect(
        try NativeArtifactCodec().load(
            runID: artifacts[0].request.identity.runID, entries: document.preservedEntries,
            projectID: document.project.id
        ).result == artifacts[0].result)
    let reopened = try SimuNowDocument(package: document.makeFileWrapper())
    #expect(reopened.preservedEntries["future"] == document.preservedEntries["future"])
    #expect(try reopened.analysisConfigurationStore().entries.isEmpty)
}
@Test func n3ThreeCandidatesEqualProfilesAndMismatch() async throws {
    let project = try N3TestFixture.make()
    var configs = AnalysisConfigurationStore(projectID: project.id)
    var results: [LocalAnalysisResult] = []
    for scenario in project.scenarios {
        configs.set(n3Config(), scenarioID: scenario.id)
        let request = try AnalysisInputResolver().request(
            project: project, scenarioID: scenario.id, method: .init(kind: .airflowPreview),
            configuration: n3Config())
        results.append(try await n3Result(request))
    }
    let rows = PreviewComparisonBuilder.rows(project: project, configuration: configs, results: results)
    #expect(rows.allSatisfy { $0.result != nil })
    #expect(
        results.map {
            if case .airflowPreview(let p) = $0.payload {
                return PreviewRelationCounts(p.relations).intersects
            }
            return -1
        } == [2, 0, 1])
    configs.set(n3Config(angle: 20), scenarioID: project.scenarios[1].id)
    #expect(
        PreviewComparisonBuilder.rows(project: project, configuration: configs, results: results)[1].result
            == nil)
}

@Test func n3ZeroEmissionOffsetCannotEscapeThinObstacle() throws {
    var project = try n3Project()
    let roomID = project.geometry.rooms[0].id
    project.scenarios[0].inputs.hvac[0].ports[0].position.x = 0
    func length(_ v: Double) -> Length { .known(value: v, source: .init(kind: .user)) }
    project.geometry.obstacles = [
        .init(
            id: N3TestFixture.id(71), roomID: roomID, name: "epsilon guard",
            shape: try .init(
                BoxObstacle(
                    origin: .init(x: 0.0000003, y: 0, z: 0),
                    dimensions: .init(width: length(0.0000017), depth: length(4), height: length(3)))))
    ]
    // Foundation-only tracing also protects a source accepted by a stricter consumer.
    // P2's separate 1e-6 integrity tolerance correctly blocks this near-contact project earlier.
    let original = try n3Request()
    let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: project.scenarios[0].id)
    let request = LocalAnalysisRequest(
        identity: original.identity, method: original.method,
        resolvedInput: .init(
            snapshot: snapshot, configuration: original.resolvedInput.configuration,
            adoptedAssumptions: original.resolvedInput.adoptedAssumptions),
        snapshotHash: original.snapshotHash, computationHash: original.computationHash,
        limits: original.limits)
    #expect(throws: AirflowPreviewError.noValidEmission) {
        try PreviewPathTracer.trace(AirflowPreviewInput(request: request))
    }
}
@Test func n3AABBAxisRotationRelationsAreEquivalent() throws {
    var rotated = try n3Project(obstruction: true)
    func transform(_ p: Position3D) -> Position3D { .init(x: 4 - p.y, y: p.x, z: p.z) }
    func length(_ v: Double) -> Length { .known(value: v, source: .init(kind: .user)) }
    rotated.geometry.rooms[0].shape = try .init(
        RectangularRoom(dimensions: .init(width: length(4), depth: length(6), height: length(3))))
    rotated.geometry.obstacles[0].shape = try .init(
        BoxObstacle(
            origin: .init(x: 1.5, y: 3, z: 0),
            dimensions: .init(width: length(1), depth: length(0.05), height: length(2))))
    rotated.scenarios[0].inputs.hvac[0].position = transform(rotated.scenarios[0].inputs.hvac[0].position)
    rotated.scenarios[0].inputs.hvac[0].ports[0].position = transform(
        rotated.scenarios[0].inputs.hvac[0].ports[0].position)
    rotated.scenarios[0].inputs.hvac[0].ports[0].direction = .init(x: 0, y: 1, z: 0)
    for i in rotated.scenarios[0].inputs.usage.seats.indices {
        rotated.scenarios[0].inputs.usage.seats[i].position = transform(
            rotated.scenarios[0].inputs.usage.seats[i].position)
        for j in rotated.scenarios[0].inputs.usage.seats[i].samples.indices {
            rotated.scenarios[0].inputs.usage.seats[i].samples[j].position = transform(
                rotated.scenarios[0].inputs.usage.seats[i].samples[j].position)
        }
    }
    #expect(
        try AirflowTargetAssessment.assess(n3Input(rotated)).map(\.state)
            == AirflowTargetAssessment.assess(n3Input(n3Project(obstruction: true))).map(\.state))
}
@Test func n3OpeningsReturnAndVisibilityNeverAlterRules() throws {
    var project = try n3Project()
    let id = project.geometry.rooms[0].id
    project.geometry.rooms[0].openings = [
        .init(
            id: N3TestFixture.id(80), surfaceID: project.geometry.rooms[0].surfaces[0].id, kind: .door,
            offsetU: .known(value: 0, source: .init(kind: .user)),
            offsetV: .known(value: 0, source: .init(kind: .user)),
            width: .known(value: 1, source: .init(kind: .user)),
            height: .known(value: 2, source: .init(kind: .user)))
    ]
    var returnPort = project.scenarios[0].inputs.hvac[0].ports[0]
    returnPort.id = N3TestFixture.id(22)
    returnPort.role = .return
    project.scenarios[0].inputs.hvac[0].ports.append(returnPort)
    project.scenarios[0].inputs.ventilation = [
        .init(
            roomID: id, outdoorAir: .unknown(reason: "No basis"), exhaustAir: .unknown(reason: "No basis"),
            infiltration: .unknown(reason: "No basis"), exfiltration: .unknown(reason: "No basis"),
            density: .unknown(reason: "No basis"),
            openings: [
                .init(
                    openingID: N3TestFixture.id(80),
                    openFraction: .known(value: 1, source: .init(kind: .user)))
            ])
    ]
    let input = try n3Input(project)
    let paths = try PreviewPathTracer.trace(input).paths
    #expect(input.notes.contains { $0.contains("任何开启门窗") })
    #expect(input.notes.contains { $0.contains("任何回风口仅显示") })
    #expect(paths.flatMap(\.points).allSatisfy { input.room.contains($0.position, tolerance: 1e-9) })
    #expect(paths[0].points == (try PreviewPathTracer.trace(n3Input())).paths[0].points)
}

private enum N3TestFixture {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000003-0000-4000-8000-%012d", n))! }
    private static func length(_ value: Double) -> Length {
        .known(
            value: value,
            source: .init(
                kind: .assumed, reference: "synthetic.N3", note: "Synthetic geometry, not measured."))
    }
    static func obstacles(enabled: Bool) throws -> [Obstacle] {
        enabled
            ? [
                .init(
                    id: id(70), roomID: id(1), name: "F-B 0.05 m 薄盒",
                    shape: try .init(
                        BoxObstacle(
                            origin: .init(x: 3, y: 1.5, z: 0),
                            dimensions: .init(width: length(0.05), depth: length(1), height: length(2)))))
            ] : []
    }
    static func make() throws -> ProjectDocument {
        let room = Room(
            id: id(1), name: "Synthetic 6×4×3",
            shape: try .init(
                RectangularRoom(dimensions: .init(width: length(6), depth: length(4), height: length(3)))),
            northAngle: .unknown(reason: "Synthetic"),
            surfaces: SurfaceFace.allCases.enumerated().map { .init(id: id(2 + $0.offset), face: $0.element) }
        )
        var scenarios: [Scenario] = []
        for (i, yaw) in [0.0, 30.0, -30.0].enumerated() {
            let offset = 0
            let split = SingleSplit(
                coolingCapacity: .unknown(reason: "No thermal basis"),
                electricalPower: .unknown(reason: "No electrical basis"),
                cop: .unknown(reason: "No performance basis"))
            let port = AirPort(
                id: id(21 + offset), role: .supply, position: .init(x: 0.05, y: 2, z: 1.5),
                direction: try AirflowDirection.unit(yawDegrees: yaw, pitchDegrees: 0),
                area: .unknown(reason: "No measurement"), volumeFlow: .unknown(reason: "No measurement"),
                speed: .unknown(reason: "No measurement"), density: .unknown(reason: "No measurement"))
            let device = HVACDevice(
                id: id(20 + offset), roomID: id(1), name: "Synthetic split", position: port.position,
                definition: try .init(split), ports: [port],
                supplyTemperature: .unknown(reason: "No measurement"))
            var scenario = Scenario.unfinished(
                id: id(10 + i), name: ["F-A 基准 0°", "F-C 候选 +30°", "F-C 候选 −30°"][i])
            scenario.inputs.hvac = [device]
            scenario.inputs.usage.seats = [
                Position3D(x: 2, y: 2, z: 1.5), .init(x: 4, y: 2, z: 1.5), .init(x: 2, y: 0.5, z: 1.5),
            ].enumerated().map {
                .init(
                    id: id(30 + $0.offset + offset), roomID: id(1), name: ["A", "B", "C"][$0.offset],
                    position: $0.element,
                    samples: [.init(id: id(40 + $0.offset + offset), position: $0.element)])
            }
            scenarios.append(scenario)
        }
        return .init(
            id: id(1000), name: "N3 synthetic 验证", spaceType: .office, geometry: .init(rooms: [room]),
            scenarios: scenarios)
    }
}

@Test @MainActor func n3CancelPendingNewInputNeverRevivesOldOverlay() async throws {
    let client = LocalAnalysisClient.production()
    let gate = N3GateClock()
    let coordinator = PreviewCoordinator(client: client, clock: gate)
    var project = try n3Project()
    let scenarioID = project.scenarios[0].id
    let input = PreviewWorkspaceInput(project: project, scenarioID: scenarioID, configuration: n3Config())
    coordinator.setEnabled(true, input: input, registry: .builtIn, persist: { _ in })
    while await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<10000 {
        if coordinator.currentResult != nil { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let original = try #require(coordinator.currentResult)
    project.scenarios[0].inputs.hvac[0].ports[0].direction = try AirflowDirection.unit(
        yawDegrees: 20, pitchDegrees: 0)
    coordinator.update(
        .init(project: project, scenarioID: scenarioID, configuration: n3Config()), registry: .builtIn,
        persist: { _ in })
    coordinator.cancel()
    #expect(coordinator.currentInputHash == nil)
    #expect(coordinator.currentResult == nil)
    #expect(coordinator.overlay.paths.isEmpty)
    #expect(coordinator.analysis.results[original.identity.runID] != nil)
    await gate.release()
    await client.shutdown()
}
@Test @MainActor func n3CurrentResultSurvivesHistoryPressureAndSameHashRecovery() async throws {
    let client = LocalAnalysisClient.production()
    let gate = N3GateClock()
    let coordinator = PreviewCoordinator(client: client, clock: gate)
    let project = try n3Project()
    let scenarioID = project.scenarios[0].id
    let input = PreviewWorkspaceInput(project: project, scenarioID: scenarioID, configuration: n3Config())
    coordinator.setEnabled(true, input: input, registry: .builtIn, persist: { _ in })
    while await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<10000 {
        if coordinator.analysis.persistence.values.contains(.saved) { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let current = try #require(coordinator.currentResult)
    var others: [NativeAnalysisArtifact] = []
    for index in 0..<13 {
        var candidate = project
        candidate.scenarios[0].inputs.hvac[0].ports[0].direction = try AirflowDirection.unit(
            yawDegrees: Double(index + 30), pitchDegrees: 0)
        let request = try n3Request(candidate, id: N3TestFixture.id(50000 + index))
        let result = try await n3Result(request)
        others.append(try NativeArtifactCodec().make(request: request, result: result))
    }
    coordinator.analysis.restore(others)
    #expect(coordinator.analysis.results.count <= 12)
    #expect(coordinator.currentResult?.identity == current.identity)
    coordinator.update(input, registry: .builtIn, persist: { _ in })
    while await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<1000 {
        if !coordinator.isPending { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(coordinator.currentResult?.identity == current.identity)
    coordinator.stop()
    await client.shutdown()
}
@Test func n3CacheBoundaryNotesMatchNewSnapshotAfterReturnChange() async throws {
    let client = LocalAnalysisClient.production()
    let initial = try n3Request()
    var first: LocalAnalysisResult?
    for await event in try await client.submit(initial) { if let result = event.result { first = result } }
    var project = try n3Project()
    var returnPort = project.scenarios[0].inputs.hvac[0].ports[0]
    returnPort.id = N3TestFixture.id(22)
    returnPort.role = .return
    project.scenarios[0].inputs.hvac[0].ports.append(returnPort)
    let request = try n3Request(project)
    #expect(request.snapshotHash != initial.snapshotHash)
    #expect(request.computationHash == initial.computationHash)
    var second: LocalAnalysisResult?
    for await event in try await client.submit(request) { if let result = event.result { second = result } }
    #expect(second?.provenance.cacheHit == true)
    #expect(first?.payload == second?.payload)
    #expect(
        AnalysisReadinessEvaluator().evaluate(
            project: project, scenarioID: project.scenarios[0].id, capability: .airflowPreview,
            configuration: n3Config()
        ).warnings.contains { $0.code == "preview_return_not_simulated" })
    await client.shutdown()
}

private func n3BudgetRequest() throws -> LocalAnalysisRequest {
    var project = try n3Project()
    let roomID = project.geometry.rooms[0].id
    func length(_ value: Double) -> Length {
        .known(value: value, source: .init(kind: .user, note: "synthetic budget fixture"))
    }
    project.geometry.obstacles = try (0..<128).map { index in
        .init(
            id: N3TestFixture.id(60000 + index), roomID: roomID, name: "budget box \(index)",
            shape: try .init(
                BoxObstacle(
                    origin: .init(
                        x: 0.2 + Double(index % 8) * 0.3, y: 0.05 + Double(index / 8) * 0.1, z: 2.7),
                    dimensions: .init(width: length(0.03), depth: length(0.03), height: length(0.1)))))
    }
    project.scenarios[0].inputs.usage.seats = (0..<512).map { index in
        let point = Position3D(x: 0.2 + Double(index % 64) * 0.07, y: 0.2 + Double(index / 64) * 0.4, z: 1.5)
        return .init(
            id: N3TestFixture.id(61000 + index), roomID: roomID, name: "budget target \(index)",
            position: point, samples: [.init(id: N3TestFixture.id(62000 + index), position: point)])
    }
    return try n3Request(project, config: n3Config(paths: 64, segments: 128, length: 3))
}
@Test func n3FullBudgetPerformance() async throws {
    let request = try n3BudgetRequest()
    let clock = ContinuousClock()
    var times: [Double] = []
    var execution: LocalAnalysisExecution?
    for _ in 0..<30 {
        let began = clock.now
        execution = try await n3Execution(request)
        let elapsed = began.duration(to: clock.now).components
        times.append((Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * 1000)
    }
    let sorted = times.sorted()
    let p50 = sorted[sorted.count / 2]
    let p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
    let payload = try #require(execution?.payload)
    let result = LocalAnalysisResult(
        identity: request.identity, method: request.method, checks: .init(state: .passed),
        assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: payload)
    let bytes = try NativeAnalysisCodec().encodeResult(result).count
    let began = clock.now
    let task = Task.detached { try await n3Execution(request) }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Cancel should be terminal")
    } catch is CancellationError {} catch { Issue.record("Unexpected error \(error)") }
    let cancelled = began.duration(to: clock.now).components
    let cancelMS = (Double(cancelled.seconds) + Double(cancelled.attoseconds) / 1e18) * 1000
    var activeCancelMS: Double?
    var completedBeforeCancel = 0
    // A timer may wake after a short optimized Release trace already completed.
    // Keep that outcome separate; only measure an acknowledged running cancel.
    for _ in 0..<5 {
        let latch = N3TraceStartLatch()
        let running = Task.detached {
            try await AirflowPreviewExecutor().execute(request) { fraction in
                if fraction == 0.1 { await latch.markStarted() }
                if fraction == 0.65 { await latch.markTraceFinished() }
            }
        }
        while !(await latch.started) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(5))
        if await latch.traceFinished {
            _ = try await running.value
            completedBeforeCancel += 1
            continue
        }
        let cancelBegan = clock.now
        running.cancel()
        do {
            _ = try await running.value
            completedBeforeCancel += 1
        } catch is CancellationError {
            let elapsed = cancelBegan.duration(to: clock.now).components
            activeCancelMS = (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * 1000
            break
        } catch { Issue.record("Unexpected running cancellation \(error)") }
    }
    var metrics: [String: Any] = [
        "method": "airflowPreview.v1", "profile": "genericCone.v1", "rounds": 30, "pathBudget": 64,
        "segmentBudget": 128, "obstacles": 128, "targets": 512, "executorP50MS": p50, "executorP95MS": p95,
        "immediateCancelObservedMS": cancelMS,
        "runningTraceCancelObservedMS": activeCancelMS.map { $0 as Any } ?? NSNull(),
        "runningTraceCancelSampleState": activeCancelMS == nil
            ? "unavailable: trace completed before each timer cancellation"
            : "CancellationError after progress=0.1 and approximately 5ms execution",
        "traceCompletedBeforeTimerCancelAttempts": completedBeforeCancel,
        "resultBytes": bytes,
        "configuration": _isDebugAssertConfiguration() ? "Debug" : "Release", "gpuFPS": "not measured",
    ]
    if case .airflowPreview(let value) = payload {
        metrics["actualPaths"] = value.paths.count
        metrics["actualSegments"] = value.paths.reduce(0) { $0 + max(0, $1.points.count - 1) }
    }
    #if canImport(Darwin)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        metrics["testProcessMaxRSSBytes"] = usage.ru_maxrss
    #endif
    let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    print("N3 performance: " + String(decoding: data, as: UTF8.self))
    if let directory = ProcessInfo.processInfo.environment["SIMUNOW_N3_PERF_DIR"] {
        try data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                _isDebugAssertConfiguration() ? "debug-performance.json" : "release-performance.json"))
    }
    #expect(bytes <= NativeArtifactCodec.maximumResultBytes)
}
@Test @MainActor func n3MaximumMergedPathEntitiesAndRebuildBudget() throws {
    if #available(macOS 15, iOS 18, *) {
        let project = try n3Project()
        let scene = RoomSceneBuilder.build(project: project, scenarioID: project.scenarios[0].id)
        let controller = RoomSceneController(bounds: scene.bounds)
        controller.reconcile(descriptor: scene, selection: nil, dark: false)
        let baseline = controller.statistics.entityCount
        let overlay = RoomSceneOverlay(
            paths: (0..<64).map { path in
                .init(
                    id: "synthetic-budget-\(path)",
                    points: (0...128).map {
                        .init(x: 0.05 + Double($0) * 5.9 / 128, y: 0.1 + Double(path) * 3.8 / 63, z: 1.5)
                    })
            }, explanation: "synthetic renderer budget, not a computed run")
        let prepared = try overlay.preparedFor3D()
        let clock = ContinuousClock()
        let began = clock.now
        controller.reconcile(descriptor: scene, overlay: prepared, selection: nil, dark: false)
        let duration = began.duration(to: clock.now).components
        print(
            "N3 MainActor mesh/entity install 64x128: \(Double(duration.seconds)*1000+Double(duration.attoseconds)/1e15) ms; pure arrays prepared separately"
        )
        #expect(controller.statistics.entityCount == baseline + 64)
        #expect(controller.statistics.overlayPathCount == 64)
        #expect(controller.overlayRenderingIssue == nil)
        let count = controller.statistics.entityCount
        controller.orbit(horizontalDegrees: 15)
        controller.reconcile(descriptor: scene, overlay: prepared, selection: nil, dark: false)
        #expect(controller.statistics.entityCount == count)
        controller.suspend()
        #expect(controller.statistics.entityCount == 1)
    }
}

@Test func n3ConfigurationDraftRejectsStaleInvalidTextAndRetainsHiddenFields() throws {
    let project = try n3Project()
    let scenario = project.scenarios[0].id
    let source = SourceRecord(kind: .assumed, note: "Explicit synthetic display profile")
    let original = AnalysisConfiguration(
        payload: .airflowPreview(
            .init(lengthMeters: 4, pathCount: 16, maximumSegments: 64, minimumStrength: 0.02, source: source)),
        acceptedAssumptions: [.genericCone])
    var configs = AnalysisConfigurationStore(projectID: project.id)
    configs.set(original, scenarioID: scenario)
    var draft = AirflowPreviewConfigurationDraft(project: project, scenarioID: scenario, store: configs)
    draft.angleText = "15"
    let updated = try draft.applying(
        currentProject: project, currentScenarioID: scenario, currentStore: configs)
    guard case .airflowPreview(let value) = updated.entries[0].configuration.payload else {
        Issue.record("Wrong configuration")
        return
    }
    #expect(value.lengthMeters == 4)
    #expect(value.maximumSegments == 64)
    #expect(value.minimumStrength == 0.02)
    #expect(value.source == source)
    #expect(value.halfAngleDegrees == 15)
    #expect(throws: PreviewConfigurationEditingError.staleDraft) {
        try draft.applying(
            currentProject: project, currentScenarioID: N3TestFixture.id(11), currentStore: configs)
    }
    var newer = project
    newer.name = "external edit"
    #expect(throws: PreviewConfigurationEditingError.staleDraft) {
        try draft.applying(currentProject: newer, currentScenarioID: scenario, currentStore: configs)
    }
    draft.radiusText = "0.0.5"
    #expect(throws: (any Error).self) {
        try draft.applying(currentProject: project, currentScenarioID: scenario, currentStore: configs)
    }
}

@Test func n3BroadPhasePreservesLinearClosedSlabAndTie() throws {
    let input = try AirflowPreviewInput(request: n3BudgetRequest())
    let index = input.collisionIndex
    for i in 0..<200 {
        let a = Position3D(x: Double(i % 10) * 0.35, y: Double(i % 16) * 0.1, z: 2.75)
        let b = Position3D(x: 5, y: Double((i * 7) % 20) * 0.1, z: 2.75)
        #expect(
            index.firstObstacle(from: a, to: b, tolerance: 1e-10)
                == SegmentIntersection.firstObstacle(
                    from: a, to: b, obstacles: input.obstacles, tolerance: 1e-10))
    }
}

@Test func n3NearNeighbourTieSetIsGlobalAndTraversalIndependent() {
    let tolerance = 1e-6
    let offsets = [1.0, 1.0 + 0.9 * tolerance, 1.0 + 1.8 * tolerance]
    let IDs = [N3TestFixture.id(70003), N3TestFixture.id(70002), N3TestFixture.id(70001)]
    let values = zip(offsets, IDs).map {
        PreviewObstacle(
            id: $1, bounds: .init(origin: .init(x: $0, y: 0, z: 0), size: .init(x: 0.1, y: 1, z: 1)))
    }
    for obstacles in [values, Array(values.reversed()), [values[1], values[2], values[0]]] {
        let a = Position3D(x: 0, y: 0.5, z: 0.5)
        let b = Position3D(x: 2, y: 0.5, z: 0.5)
        let linear = SegmentIntersection.firstObstacle(
            from: a, to: b, obstacles: obstacles, tolerance: tolerance)
        let indexed = PreviewCollisionIndex(obstacles: obstacles).firstObstacle(
            from: a, to: b, tolerance: tolerance)
        #expect(linear?.obstacleID == IDs[1])
        #expect(indexed == linear)
    }
}
@Test func n3PublicMeshBuilderRejectsEmptySingleNonfiniteAndZeroLength() {
    for points in [
        [], [Position3D(x: 0, y: 0, z: 0)], [.init(x: 0, y: 0, z: 0), .init(x: 0, y: 0, z: 0)],
        [.init(x: 0, y: 0, z: 0), .init(x: .infinity, y: 0, z: 0)],
    ] {
        #expect(throws: (any Error).self) {
            try AirflowPathMeshBuilder.build(.init(id: "invalid", points: points))
        }
    }
}

private actor N3TraceStartLatch {
    private(set) var started = false
    private(set) var traceFinished = false
    func markStarted() { started = true }
    func markTraceFinished() { traceFinished = true }
}
@Test func n3ClientFullBudgetEndToEndAndRunningCancellation() async throws {
    let clock = ContinuousClock()
    let prepareBegan = clock.now
    let base = try n3BudgetRequest()
    func milliseconds(_ from: ContinuousClock.Instant) -> Double {
        let d = from.duration(to: clock.now).components
        return (Double(d.seconds) + Double(d.attoseconds) / 1e18) * 1000
    }
    let prepareMS = milliseconds(prepareBegan)
    var breakdown: [String: Double] = [:]
    func measure(_ key: String, _ body: () throws -> Void) throws {
        let began = clock.now
        try body()
        breakdown[key] = milliseconds(began)
    }
    try measure("encodeRequestMS") { _ = try NativeAnalysisCodec().encodeRequest(base) }
    try measure("hashInputMS") { _ = try AnalysisHasher().hashes(base.resolvedInput, method: base.method) }
    try measure("validateInputMS") { try AnalysisInputResolver().validate(base) }
    try measure("readinessMS") {
        let snapshot = base.resolvedInput.snapshot
        let project = ProjectDocument(
            id: snapshot.projectID, name: "Benchmark", spaceType: .office,
            geometry: snapshot.geometry,
            scenarios: [
                .init(
                    id: snapshot.scenarioID, name: "Benchmark",
                    inputs: snapshot.inputs, evaluation: snapshot.evaluation)
            ])
        _ = AnalysisReadinessEvaluator().evaluate(
            project: project, scenarioID: snapshot.scenarioID,
            capability: .airflowPreview, configuration: base.resolvedInput.configuration)
    }
    let client = try LocalAnalysisClient(executors: [AirflowPreviewExecutor()], maximumCacheEntries: 0)
    func request(_ index: Int) -> LocalAnalysisRequest {
        .init(
            identity: .init(
                runID: N3TestFixture.id(80000 + index), scenarioID: base.identity.scenarioID,
                inputHash: base.identity.inputHash), method: base.method, resolvedInput: base.resolvedInput,
            snapshotHash: base.snapshotHash, computationHash: base.computationHash, limits: base.limits)
    }
    var times: [Double] = []
    var lastResult: LocalAnalysisResult?
    for index in 0..<10 {
        let began = clock.now
        for await event in try await client.submit(request(index)) {
            if let result = event.result { lastResult = result }
        }
        times.append(milliseconds(began))
    }
    let final = try #require(lastResult)
    try measure("encodeResultMS") { _ = try NativeAnalysisCodec().encodeResult(final) }
    let artifactBegan = clock.now
    let artifact = try NativeArtifactCodec().make(request: request(9), result: final)
    let artifactMS = milliseconds(artifactBegan)
    let snapshot = base.resolvedInput.snapshot
    let project = ProjectDocument(
        id: snapshot.projectID, name: "Benchmark", spaceType: .office,
        geometry: snapshot.geometry,
        scenarios: [
            .init(
                id: snapshot.scenarioID, name: "Benchmark",
                inputs: snapshot.inputs, evaluation: snapshot.evaluation)
        ])
    let document = try SimuNowDocument(project: project)
    try measure("documentAppendMS") {
        _ = try document.appendingNativeAnalysis(artifact, expectedProjectID: project.id)
    }
    let cancellationRequest = request(20)
    var cancelBegan: ContinuousClock.Instant?
    var cancelMS: Double?
    var terminalCount = 0
    for await event in try await client.submit(cancellationRequest) {
        if event.stage == .progress, event.progress == 0.1 {
            try await Task.sleep(for: .milliseconds(5))
            cancelBegan = clock.now
            await client.cancel(runID: cancellationRequest.identity.runID)
        }
        if event.stage.isTerminal {
            terminalCount += 1
            #expect(event.stage == .cancelled)
            if let began = cancelBegan { cancelMS = milliseconds(began) }
        }
    }
    #expect(terminalCount == 1)
    #expect(cancelMS != nil)
    let sorted = times.sorted()
    let metrics: [String: Any] = [
        "rounds": 10, "clientSubmitToCompletedP50MS": sorted[5], "clientSubmitToCompletedP95MS": sorted[9],
        "requestPreparationOnceMS": prepareMS, "artifactEncodingOnceMS": artifactMS,
        "artifactBytes": artifact.byteCount, "clientRunningCancelToTerminalMS": cancelMS ?? -1,
        "breakdown": breakdown,
        "includes":
            "Client input validate/hash, executor, checks/result codec; excludes request preparation, artifact/persistence and 250ms debounce",
        "gpuFPS": "not measured", "configuration": _isDebugAssertConfiguration() ? "Debug" : "Release",
    ]
    let data = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    print("N3 client benchmark: " + String(decoding: data, as: UTF8.self))
    if let directory = ProcessInfo.processInfo.environment["SIMUNOW_N3_PERF_DIR"] {
        try data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                _isDebugAssertConfiguration()
                    ? "debug-client-performance.json" : "release-client-performance.json"))
    }
    await client.shutdown()
}

@Test @MainActor func n3PackageIntegrityIssuesBlockPreviewButUnusedWeatherDoesNot() async throws {
    let project = try n3Project()
    let scenarioID = project.scenarios[0].id
    let client = LocalAnalysisClient.production()
    let gate = N3GateClock()
    let coordinator = PreviewCoordinator(client: client, clock: gate)
    let damaged = ValidationIssue(
        code: "weather_asset_hash", path: "/assets/weather/file.epw", blocks: [.projectIntegrity],
        message: "Attachment hash mismatch")
    coordinator.setEnabled(
        true,
        input: .init(
            project: project, scenarioID: scenarioID, configuration: n3Config(), additionalIssues: [damaged]),
        registry: .builtIn, persist: { _ in })
    while await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<1000 {
        if !coordinator.isPending { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(coordinator.currentResult == nil)
    #expect(coordinator.analysis.records.isEmpty)
    #expect(coordinator.readiness?.blockers.contains { $0.code == "weather_asset_hash" } == true)
    let unused = ValidationIssue(
        code: "weather_unprovided", path: "/scenarios/0/inputs/environment/weather",
        blocks: [.inputPreparation], message: "No adopted weather")
    coordinator.update(
        .init(
            project: project, scenarioID: scenarioID, configuration: n3Config(), additionalIssues: [unused]),
        registry: .builtIn, persist: { _ in })
    while await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<10000 {
        if coordinator.currentResult != nil { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(coordinator.currentResult?.checks.state == .passed)
    coordinator.stop()
    await client.shutdown()
}

@Test func n3StreamingJSONMatchesFoundationStringsAndLosslessTokens() throws {
    let strings = [
        "", "a/b", "\"quoted\"\\", "é中文😀", "\u{2028}\u{2029}",
        String((0...31).compactMap(UnicodeScalar.init).map(Character.init)),
    ]
    for string in strings {
        let expected = try JSONEncoder().encode(string)
        #expect(try JSONValue.string(string).data() == expected)
        #expect(try JSONValue(data: expected) == .string(string))
    }
    let tree = JSONValue.object([
        "uint": .number("18446744073709551615"),
        "opaque": .number("1.2300e+4"), "negativeZero": .number("-0.0"),
        "escape": .string("a/b\n"),
    ])
    #expect(try JSONValue(data: tree.data()) == tree)
    for malformed in ["01", "NaN", "1e", "1.2x", "\"bad\nstring\""] {
        #expect(throws: (any Error).self) { _ = try JSONValue(data: Data(malformed.utf8)) }
    }
}
@Test @MainActor func n3PendingAndUnconfiguredScenarioNeverShowPreviousStage() async throws {
    let project = try n3Project()
    let scenario = project.scenarios[0].id
    let gate = N3GateClock()
    let coordinator = PreviewCoordinator(client: LocalAnalysisClient.production(), clock: gate)
    let input = PreviewWorkspaceInput(project: project, scenarioID: scenario, configuration: n3Config())
    coordinator.setEnabled(true, input: input, registry: .builtIn, persist: { _ in })
    while await gate.count() == 0 { await Task.yield() }
    await gate.release()
    for _ in 0..<10000 {
        if coordinator.currentResult != nil { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(coordinator.currentStage == .completed)
    coordinator.update(input, registry: .builtIn, persist: { _ in })
    #expect(coordinator.isPending)
    #expect(coordinator.currentStage == nil)
    #expect(coordinator.currentResult == nil)
    coordinator.update(
        .init(project: project, scenarioID: N3TestFixture.id(99999), configuration: nil),
        registry: .builtIn, persist: { _ in })
    #expect(!coordinator.isPending)
    #expect(coordinator.currentStage == nil)
    #expect(coordinator.currentFailure == nil)
    #expect(coordinator.inputFailure == nil)
    #expect(coordinator.currentResult == nil)
    #expect(!coordinator.analysis.results.isEmpty)
    coordinator.stop()
}
@Test func n3SidefileAppendReusesOnlyMatchingValidatedInputAndChecksFullBudget() async throws {
    let request = try AnalysisInputResolver().request(
        project: n3Project(),
        scenarioID: N3TestFixture.id(10), method: .init(kind: .airflowPreview), configuration: n3Config())
    let execution = try await AirflowPreviewExecutor().execute(request) { _ in }
    let result = LocalAnalysisResult(
        identity: request.identity, method: request.method,
        checks: execution.checks, assumptions: request.resolvedInput.adoptedAssumptions,
        elapsedSeconds: 0, payload: execution.payload)
    let artifact = try NativeArtifactCodec().make(request: request, result: result)
    let document = try SimuNowDocument(project: n3Project())
    let next = try document.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    #expect(next.project == document.project)
    #expect(next.nativeSidefileRevision != document.nativeSidefileRevision)
    #expect(
        try NativeArtifactCodec().load(
            runID: result.identity.runID,
            entries: next.preservedEntries, projectID: document.project.id
        ).result == result)
    var malformed = document
    malformed.project.schemaVersion = 999
    #expect(throws: (any Error).self) {
        _ = try malformed.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    }
    var changed = document
    changed.project.name = "Changed public project"
    let changedNext = try changed.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    #expect(
        try ProjectCodec(registry: .builtIn).decode(
            changedNext.makeFileWrapper().fileWrappers!["project.json"]!.regularFileContents!
        ).name == changed.project.name)
    let limited = try SimuNowDocument(project: n3Project(), limits: .init(maximumEntries: 3))
    #expect(throws: (any Error).self) {
        _ = try limited.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    }
    let configurations = AnalysisConfigurationStore(
        projectID: document.project.id,
        entries: [
            .init(scenarioID: request.identity.scenarioID, configuration: request.resolvedInput.configuration)
        ])
    let damaged = ValidationIssue(
        code: "weather_asset_hash", path: "/assets/weather/file.epw",
        blocks: [.projectIntegrity], message: "Corrupt attachment")
    #expect(
        PreviewComparisonBuilder.rows(
            project: document.project, configuration: configurations,
            results: [result], additionalIssues: [damaged]
        ).allSatisfy { $0.result == nil })
}

@Test func n3CanonicalFastNumbersMatchLosslessNormalizationAndCancellation() async throws {
    let integerSchema = JSONValue.object(["type": .string("integer")])
    let numberSchema = JSONValue.object(["type": .string("number")])
    for token in ["0", "-0", "1", "-17", "1.0", "1e0", "18446744073709551615"] {
        let node = JSONValue.number(token)
        let baseline: NativeCanonicalValue
        if let signed = try? JSONTreeCoding.decode(Int64.self, from: node) {
            baseline = .integer(signed)
        } else {
            baseline = .unsigned(try JSONTreeCoding.decode(UInt64.self, from: node))
        }
        #expect(
            try AnalysisCanonicalizer.bytes(
                AnalysisCanonicalizer.value(
                    node,
                    schema: integerSchema, root: integerSchema)) == AnalysisCanonicalizer.bytes(baseline))
    }
    for token in ["-0.0", "0", "1.2300e+4", "-1.2e-30"] {
        let node = JSONValue.number(token)
        #expect(
            try AnalysisCanonicalizer.bytes(
                AnalysisCanonicalizer.value(
                    node,
                    schema: numberSchema, root: numberSchema))
                == AnalysisCanonicalizer.bytes(
                    .double(JSONTreeCoding.decode(Double.self, from: node))))
    }
    let cancellation = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        _ = try JSONValue.array(Array(repeating: .string("test"), count: 100000)).data()
    }
    cancellation.cancel()
    do {
        try await cancellation.value
        Issue.record("Cancelled encoding should not finish")
    } catch is CancellationError {} catch { Issue.record("Wrong cancellation failure: \(error)") }
}

@Test func n3ValidationWithoutSerializationRejectsMalformedOpaqueNumberTokens() throws {
    for token in ["01", "+1", "1e", "NaN", "1.2x"] {
        #expect(throws: (any Error).self) {
            _ = try JSONTreeCoding.encode(JSONValue.object(["opaque": .number(token)]))
        }
        var project = try n3Project()
        project.geometry.obstacles = [
            .init(
                id: UUID(), roomID: project.geometry.rooms[0].id,
                name: "Future opaque",
                shape: .init(
                    kind: "future.n3.box", payloadVersion: 99,
                    payload: .object(["number": .number(token)])))
        ]
        #expect(throws: (any Error).self) { try ProjectCodec(registry: .builtIn).validate(project) }
        #expect(throws: (any Error).self) { _ = try ProjectCodec(registry: .builtIn).encode(project) }
    }
}

@Test func n3TypicalProductionLifecyclePerformance() async throws {
    let clock = ContinuousClock()
    func ms(_ from: ContinuousClock.Instant) -> Double {
        let d = from.duration(to: clock.now).components
        return (Double(d.seconds) + Double(d.attoseconds) / 1e18) * 1000
    }
    let project = try n3Project()
    let scenarioID = project.scenarios[0].id
    let configuration = n3Config(paths: 32)
    let client = try LocalAnalysisClient(executors: [AirflowPreviewExecutor()], maximumCacheEntries: 0)
    var clientTimes: [Double] = []
    var preparationTimes: [Double] = []
    var artifactTimes: [Double] = []
    var appendTimes: [Double] = []
    var lastBytes = 0
    let document = try SimuNowDocument(project: project)
    for _ in 0..<30 {
        let beforePrepare = clock.now
        let request = try AnalysisInputResolver().request(
            project: project, scenarioID: scenarioID,
            method: .init(kind: .airflowPreview), configuration: configuration)
        preparationTimes.append(ms(beforePrepare))
        let beforeClient = clock.now
        var completed: LocalAnalysisResult?
        for await event in try await client.submit(request) {
            if let result = event.result { completed = result }
        }
        clientTimes.append(ms(beforeClient))
        let result = try #require(completed)
        guard case .airflowPreview(let payload) = result.payload else {
            Issue.record("Wrong payload")
            return
        }
        #expect(payload.paths.count == 32)
        #expect(payload.relations.count == 3)
        #expect(PreviewRelationCounts(payload.relations).intersects == 2)
        let beforeArtifact = clock.now
        let artifact = try NativeArtifactCodec().make(request: request, result: result)
        artifactTimes.append(ms(beforeArtifact))
        lastBytes = artifact.byteCount
        let beforeAppend = clock.now
        try await MainActor.run {
            _ = try document.appendingNativeAnalysis(artifact, expectedProjectID: project.id)
        }
        appendTimes.append(ms(beforeAppend))
    }
    func quantiles(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        return ["p50MS": sorted[15], "p95MS": sorted[28]]
    }
    let metrics: [String: Any] = [
        "rounds": 30, "paths": 32, "targets": 3, "obstacles": 0,
        "requestPreparation": quantiles(preparationTimes), "requestPreparationFirstMS": preparationTimes[0],
        "clientSubmitToCompleted": quantiles(clientTimes),
        "artifactEncoding": quantiles(artifactTimes),
        "documentAppendIncludingMainActorHop": quantiles(appendTimes),
        "artifactBytes": lastBytes, "cache": "disabled: production AirflowPreviewExecutor executes every run",
        "configuration": _isDebugAssertConfiguration() ? "Debug" : "Release", "gpuFPS": "not measured",
        "notes":
            "Client timing excludes 250ms debounce, request and artifact; preparation includes one cold schema load in round 1",
    ]
    let bytes = try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    print("N3 typical lifecycle benchmark: " + String(decoding: bytes, as: UTF8.self))
    if let directory = ProcessInfo.processInfo.environment["SIMUNOW_N3_PERF_DIR"] {
        try bytes.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                _isDebugAssertConfiguration()
                    ? "debug-typical-performance.json" : "release-typical-performance.json"))
    }
    await client.shutdown()
}

@Test func n3FullProjectIntegrityGateBlocksInvalidTargetsInAnyScenario() throws {
    for position in [Position3D(x: -1, y: 2, z: 1.5), Position3D(x: 3.02, y: 2, z: 1.5)] {
        var project = try n3Project(obstruction: true)
        var other = project.scenarios[0]
        other.id = N3TestFixture.id(77777)
        other.inputs.usage.seats[0].samples[0].position = position
        project.scenarios.append(other)
        let report = AnalysisReadinessEvaluator().evaluate(
            project: project,
            scenarioID: project.scenarios[0].id, capability: .airflowPreview, configuration: n3Config())
        #expect(!report.eligible)
        #expect(report.blockers.contains { ["point_bounds", "point_in_solid"].contains($0.code) })
        #expect(throws: (any Error).self) { _ = try n3Request(project) }
        let viewing = AnalysisReadinessEvaluator().evaluate(
            project: project,
            scenarioID: project.scenarios[0].id, capability: .roomView)
        #expect(viewing.warnings.contains { ["point_bounds", "point_in_solid"].contains($0.code) })
    }
}

@Test func n3EmptySeatsAndLegalToleranceMarkerRemainUnevaluatedWithoutAdvice() async throws {
    for empty in [true, false] {
        var project = try n3Project()
        project.scenarios[0].inputs.usage.seats =
            empty
            ? []
            : [
                .init(
                    id: N3TestFixture.id(88888), roomID: project.geometry.rooms[0].id,
                    name: "Within project coordinate tolerance, outside preview",
                    position: .init(x: -0.5e-6, y: 2, z: 1.5))
            ]
        let request = try n3Request(project)
        let client = LocalAnalysisClient.production()
        var completed: LocalAnalysisResult?
        for await event in try await client.submit(request) {
            if let result = event.result { completed = result }
        }
        let result = try #require(completed)
        guard case .airflowPreview(let payload) = result.payload else {
            Issue.record("Wrong payload")
            return
        }
        #expect(payload.notes.contains { $0.contains("无可评价关注点") })
        if empty {
            #expect(payload.relations.isEmpty)
        } else {
            #expect(payload.relations.count == 1)
            #expect(payload.relations[0].state == .notEvaluated)
            #expect(payload.relations[0].isPositionMarker)
            #expect(payload.relations[0].missingReason != nil)
        }
        await client.shutdown()
    }
}
