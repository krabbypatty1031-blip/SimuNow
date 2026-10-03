import Foundation
import Testing
import SimuCore
import SimuSimulation
@testable import SimuWorkspace

private func lifecycleProject() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    var project = try ProjectCodec(registry: .builtIn).decode(
        Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    project.scenarios[0].inputs.environment.weather = nil
    return project
}
private func lifecycleRequest(id: UUID = UUID()) throws -> LocalAnalysisRequest {
    let project = try lifecycleProject()
    return try AnalysisInputResolver().request(
        project: project, scenarioID: project.scenarios[0].id,
        method: .init(kind: .airflowPreview),
        configuration: .init(payload: .airflowPreview(.init()), acceptedAssumptions: [.genericCone]),
        runID: id)
}

private func lifecycleResult(_ request: LocalAnalysisRequest) -> LocalAnalysisResult {
    .init(identity: request.identity, method: request.method, checks: .init(state: .passed),
          assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0,
          payload: .airflowPreview(.init(
            profileID: "simunow.preview.genericCone", profileVersion: 1,
            paths: [.init(id: 0, points: [.init(position: .init(x: 1, y: 1, z: 1), strength: 1)], termination: .lengthLimit)],
            relations: [], validEmissionCount: 1)))
}

private actor LifecycleCompletedClient: LocalAnalysisSubmitting {
    func submit(_ request: LocalAnalysisRequest) async throws -> AsyncStream<LocalAnalysisEvent> {
        AsyncStream { continuation in
            continuation.yield(.init(runID: request.identity.runID, scenarioID: request.identity.scenarioID,
                                     sequence: 0, stage: .completed, result: lifecycleResult(request)))
            continuation.finish()
        }
    }
    func cancel(runID: UUID) async {}
}

/// A deterministic suspension at the real artifact boundary, without time-based races.
private actor LifecycleArtifactGate: AnalysisArtifactBuilding {
    let blockedRunID: UUID
    let cooperateWithCancellation: Bool
    private var continuation: CheckedContinuation<NativeAnalysisArtifact, any Error>?
    private var input: (LocalAnalysisRequest, LocalAnalysisResult)?
    private(set) var started = false
    private(set) var cancelled = false
    init(blockedRunID: UUID, cooperateWithCancellation: Bool) {
        self.blockedRunID = blockedRunID
        self.cooperateWithCancellation = cooperateWithCancellation
    }
    func make(request: LocalAnalysisRequest, result: LocalAnalysisResult) async throws -> NativeAnalysisArtifact {
        guard request.identity.runID == blockedRunID else {
            return try NativeArtifactCodec().make(request: request, result: result)
        }
        return try await withTaskCancellationHandler(operation: {
            try await wait(request: request, result: result)
        }, onCancel: { Task { await self.cancelWait() } })
    }
    private func wait(request: LocalAnalysisRequest, result: LocalAnalysisResult) async throws -> NativeAnalysisArtifact {
        if cancelled && cooperateWithCancellation { throw CancellationError() }
        return try await withCheckedThrowingContinuation {
            input = (request, result)
            continuation = $0
            started = true
        }
    }
    private func cancelWait() {
        cancelled = true
        if cooperateWithCancellation {
            continuation?.resume(throwing: CancellationError())
            continuation = nil
            input = nil
        }
    }
    func release() {
        guard let continuation, let input else { return }
        self.continuation = nil
        self.input = nil
        do { continuation.resume(returning: try NativeArtifactCodec().make(request: input.0, result: input.1)) }
        catch { continuation.resume(throwing: error) }
    }
}

@MainActor private func lifecycleWait(_ predicate: () async -> Bool) async throws {
    let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(60))
    while !(await predicate()) && clock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
    guard await predicate() else { throw LifecycleWaitError.timeout }
}
private enum LifecycleWaitError: Error { case timeout }

private func lifecyclePowerRequest() throws -> LocalAnalysisRequest {
    let project = try lifecycleProject()
    let source = SourceRecord(kind: .user, note: "Synthetic lifecycle regression, not measured electrical use")
    let configuration = PowerEstimateConfiguration(
        requestedWindows: [.init(startMinute: 0, endMinute: 120)],
        intervals: [.init(startMinute: 0, endMinute: 120,
                          power: .known(value: 1000, source: source), basis: .declaredScenario)],
        aggregateDeviceIDs: project.scenarios[0].inputs.hvac.map(\.id),
        aggregateCoverageNote: "Explicit synthetic aggregate of the scenario devices")
    return try AnalysisInputResolver().request(project: project, scenarioID: project.scenarios[0].id,
        method: .init(kind: .powerEstimate), configuration: .init(payload: .powerEstimate(configuration)))
}

/// Internally consistent integral, but it halves the adopted frozen power.
private func counterfeitPowerExecution() -> LocalAnalysisExecution {
    .init(payload: .powerEstimate(.init(requestedWindows: [.init(startMinute: 0, endMinute: 120)],
        segments: [.init(startMinute: 0, endMinute: 120, powerWatts: 500, energyKWh: 1, basis: .declaredScenario)],
        totalEnergyKWh: 1, knownSubtotalKWh: 1)), checks: .init(state: .passed))
}
private struct CounterfeitPowerExecutor: LocalAnalysisExecutor {
    let method = AnalysisMethod(kind: .powerEstimate)
    func execute(_ request: LocalAnalysisRequest, progress: @escaping @Sendable (Double) async -> Void) async throws -> LocalAnalysisExecution {
        counterfeitPowerExecution()
    }
}
private actor CounterfeitPowerClient: LocalAnalysisSubmitting {
    func submit(_ request: LocalAnalysisRequest) async throws -> AsyncStream<LocalAnalysisEvent> {
        let execution = counterfeitPowerExecution()
        let result = LocalAnalysisResult(identity: request.identity, method: request.method, checks: execution.checks,
            assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: execution.payload)
        // This passes wire validation and its own power×time arithmetic.
        _ = try NativeAnalysisCodec().encodeResult(result)
        return AsyncStream { continuation in
            continuation.yield(.init(runID: request.identity.runID, scenarioID: request.identity.scenarioID,
                sequence: 0, stage: .completed, result: result))
            continuation.finish()
        }
    }
    func cancel(runID: UUID) async { }
}

private actor DuplicatePowerClient: LocalAnalysisSubmitting {
    func submit(_ request: LocalAnalysisRequest) async throws -> AsyncStream<LocalAnalysisEvent> {
        guard case .powerEstimate(let configuration) = request.resolvedInput.configuration.payload else { throw LifecycleWaitError.timeout }
        let actual = try PowerIntegrator.integrate(configuration, deviceIDs: request.resolvedInput.snapshot.inputs.hvac.map(\.id))
        let valid = LocalAnalysisResult(identity: request.identity, method: request.method, checks: .init(state: .passed),
            assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: .powerEstimate(actual))
        let counterfeit = LocalAnalysisResult(identity: request.identity, method: request.method, checks: .init(state: .passed),
            assumptions: request.resolvedInput.adoptedAssumptions, elapsedSeconds: 0, payload: counterfeitPowerExecution().payload)
        return AsyncStream { continuation in
            continuation.yield(.init(runID: request.identity.runID, scenarioID: request.identity.scenarioID, sequence: 0, stage: .accepted))
            continuation.yield(.init(runID: request.identity.runID, scenarioID: request.identity.scenarioID, sequence: 0, stage: .completed, result: counterfeit))
            continuation.yield(.init(runID: request.identity.runID, scenarioID: request.identity.scenarioID, sequence: 1, stage: .completed, result: valid))
            continuation.finish()
        }
    }
    func cancel(runID: UUID) async { }
}

@Test @MainActor func duplicateInvalidEventCannotFailTheCurrentValidRun() async throws {
    let request = try lifecyclePowerRequest()
    let coordinator = AnalysisCoordinator(client: DuplicatePowerClient())
    coordinator.start(request) { _ in }
    try await lifecycleWait { coordinator.persistence[request.identity.runID] == .saved }
    #expect(coordinator.stage == .completed && coordinator.failure == nil)
    let result = try #require(coordinator.results[request.identity.runID])
    guard case .powerEstimate(let value) = result.payload else { Issue.record("Expected adopted power result"); return }
    #expect(value.totalEnergyKWh == 2)
}

@Test func clientRejectsCounterfeitThermalEvidenceBeforeCaching() async throws {
    let request = try lifecyclePowerRequest()
    let client = try LocalAnalysisClient(executors: [CounterfeitPowerExecutor()])
    let stream = try await client.submit(request)
    var events: [LocalAnalysisEvent] = []
    for await event in stream { events.append(event) }
    #expect(events.last?.stage == .failed)
    #expect(events.last?.failure?.code == "invalid_executor_result")
    #expect(events.allSatisfy { $0.result == nil })
    let stats = await client.statistics()
    #expect(stats.cacheCount == 0 && stats.running == 0 && stats.queued == 0)
}

@Test @MainActor func coordinatorRejectsCounterfeitThermalEvidenceBeforeRetaining() async throws {
    let request = try lifecyclePowerRequest()
    let coordinator = AnalysisCoordinator(client: CounterfeitPowerClient())
    var persisted = false
    coordinator.start(request) { _ in persisted = true }
    try await lifecycleWait { coordinator.stage == .failed }
    #expect(coordinator.failure?.code == "invalid_analysis_event")
    #expect(coordinator.results.isEmpty && coordinator.records.isEmpty && !persisted)
}

@Test @MainActor func stoppedAnalysisCancelsArtifactWorkAndCannotPersist() async throws {
    let request = try lifecycleRequest()
    let gate = LifecycleArtifactGate(blockedRunID: request.identity.runID, cooperateWithCancellation: true)
    let coordinator = AnalysisCoordinator(client: LifecycleCompletedClient(), artifactBuilder: gate)
    var persisted: [UUID] = []
    coordinator.start(request) { persisted.append($0.request.identity.runID) }
    try await lifecycleWait { await gate.started }
    coordinator.stop()
    try await lifecycleWait { await gate.cancelled }
    #expect(persisted.isEmpty)
    #expect(coordinator.activeIdentity == nil)
    #expect(coordinator.results[request.identity.runID] != nil)
    #expect(coordinator.persistence[request.identity.runID] == .notSaved)
}

@Test @MainActor func lateArtifactCannotMutateAReplacementSession() async throws {
    let old = try lifecycleRequest(), replacement = try lifecycleRequest()
    let gate = LifecycleArtifactGate(blockedRunID: old.identity.runID, cooperateWithCancellation: false)
    let coordinator = AnalysisCoordinator(client: LifecycleCompletedClient(), artifactBuilder: gate)
    var persisted: [UUID] = []
    coordinator.start(old) { persisted.append($0.request.identity.runID) }
    try await lifecycleWait { await gate.started }
    let oldSubscription = try #require(coordinator.eventSubscription)
    coordinator.start(replacement) { persisted.append($0.request.identity.runID) }
    try await lifecycleWait { coordinator.persistence[replacement.identity.runID] == .saved }
    await gate.release()
    await oldSubscription.value
    try await lifecycleWait { await gate.cancelled }
    #expect(coordinator.activeIdentity == replacement.identity)
    #expect(persisted == [replacement.identity.runID])
    #expect(coordinator.persistence[old.identity.runID] == .notSaved)
}

@Test func documentInstanceSurvivesTransactionsButChangesOnAnotherRead() throws {
    let request = try lifecycleRequest()
    let document = try SimuNowDocument(project: lifecycleProject())
    let state = WorkspaceProjectState(project: document.project, baselineScenarioID: document.project.scenarios[0].id)
    let edited = try document.applyingWorkspaceState(state)
    #expect(edited.documentInstanceID == document.documentInstanceID)
    let artifact = try NativeArtifactCodec().make(request: request, result: lifecycleResult(request))
    let appended = try edited.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    #expect(appended.documentInstanceID == document.documentInstanceID)
    #expect(appended.nativeSidefileRevision != edited.nativeSidefileRevision)
    let reopened = try SimuNowDocument(package: appended.makeFileWrapper())
    #expect(reopened.project.id == document.project.id)
    #expect(reopened.documentInstanceID != document.documentInstanceID)
    #expect(throws: (any Error).self) { try reopened.validateDocumentInstance(document.documentInstanceID) }
    try appended.validateDocumentInstance(document.documentInstanceID)
}

@Test func cachedDocumentIntegrityCannotHidePublicMetadataMutation() throws {
    var document = try SimuNowDocument(project: lifecycleProject())
    let original = document.integrityReport
    document.metadata.baselineScenarioID = UUID()
    #expect(!document.integrityReport.passes(.projectIntegrity))
    #expect(document.integrityReport.issues.contains { $0.code == "baseline_reference" })
    document.metadata.baselineScenarioID = nil
    #expect(document.integrityReport == original)
}

@Test @MainActor func sidefileAppendPreservesUndoButAnotherDocumentClearsSession() throws {
    let document = try SimuNowDocument(project: lifecycleProject())
    let store = WorkspaceStore()
    store.load(document.project)
    store.updateNativeDocumentContext(instanceID: document.documentInstanceID, sidefileRevision: document.nativeSidefileRevision)
    var edited = document.project; edited.name = "Local edit before a background result"
    try store.replaceProject(edited, actionName: "改名")
    let request = try lifecycleRequest()
    let artifact = try NativeArtifactCodec().make(request: request, result: lifecycleResult(request))
    store.preview.analysis.restore([artifact])
    let power = try lifecyclePowerRequest()
    guard case .powerEstimate(let configuration) = power.resolvedInput.configuration.payload else { throw LifecycleWaitError.timeout }
    let powerResult = LocalAnalysisResult(identity: power.identity, method: power.method, checks: .init(state: .passed),
        assumptions: power.resolvedInput.adoptedAssumptions, elapsedSeconds: 0,
        payload: .powerEstimate(try PowerIntegrator.integrate(configuration, deviceIDs: document.project.scenarios[0].inputs.hvac.map(\.id))))
    store.estimates.power.restore([try NativeArtifactCodec().make(request: power, result: powerResult)])
    let appended = try document.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    store.updateNativeDocumentContext(instanceID: appended.documentInstanceID, sidefileRevision: appended.nativeSidefileRevision)
    #expect(store.canUndo && store.preview.analysis.results.count == 1 && store.estimates.power.results.count == 1)
    store.undo()
    #expect(store.project == document.project && store.canRedo)
    let reopened = try SimuNowDocument(package: appended.makeFileWrapper())
    store.updateNativeDocumentContext(instanceID: reopened.documentInstanceID, sidefileRevision: reopened.nativeSidefileRevision)
    #expect(store.preview.analysis.results.isEmpty && store.estimates.power.results.isEmpty)
    #expect(!store.canUndo && !store.canRedo)
    #expect(store.documentInstanceID == reopened.documentInstanceID)
}

@MainActor private final class LifecycleDocumentAuthority {
    var value: SimuNowDocument
    init(_ value: SimuNowDocument) { self.value = value }
}

@Test @MainActor func latestBindingRejectsHistoryBeforeExternalChangeNotification() throws {
    let document = try SimuNowDocument(project: lifecycleProject())
    let authority = LifecycleDocumentAuthority(document)
    let store = WorkspaceStore()
    store.load(document.project)
    store.updateNativeDocumentContext(instanceID: document.documentInstanceID, sidefileRevision: document.nativeSidefileRevision)
    store.validateNativeDocumentBinding = { instance, revision in
        try authority.value.validateDocumentInstance(instance)
        if let revision, revision != authority.value.nativeSidefileRevision { throw NativeDocumentSessionError.attachmentsChanged }
    }
    try store.validateNativeDocumentContext(instanceID: document.documentInstanceID, sidefileRevision: document.nativeSidefileRevision)
    let request = try lifecycleRequest()
    let artifact = try NativeArtifactCodec().make(request: request, result: lifecycleResult(request))
    authority.value = try document.appendingNativeAnalysis(artifact, expectedProjectID: document.project.id)
    #expect(throws: (any Error).self) { try store.validateNativeDocumentContext(instanceID: document.documentInstanceID, sidefileRevision: document.nativeSidefileRevision) }
    // A writer may merge new attachments into the same instance without adopting
    // the stale loader's sidefile revision.
    try store.validateNativeDocumentContext(instanceID: document.documentInstanceID)
    authority.value = try SimuNowDocument(package: authority.value.makeFileWrapper())
    #expect(authority.value.project == document.project)
    #expect(throws: (any Error).self) { try store.validateNativeDocumentContext(instanceID: document.documentInstanceID) }
}

@Test @MainActor func rejectedUndoAndRedoKeepDocumentAndHistoryConsistent() throws {
    let original = try lifecycleProject()
    let store = WorkspaceStore(); store.load(original)
    var publications = 0
    store.onDocumentChange = { _ in publications += 1 }
    var edited = original; edited.name = "Edited"
    try store.replaceProject(edited, actionName: "改名")
    store.validateDocumentChange = { _ in throw NativeDocumentSessionError.replaced }
    store.undo()
    #expect(store.project == edited && store.canUndo && !store.canRedo && publications == 1)
    #expect(store.presentedError != nil)
    store.validateDocumentChange = nil
    store.undo()
    #expect(store.project == original && !store.canUndo && store.canRedo && publications == 2)
    store.validateDocumentChange = { _ in throw NativeDocumentSessionError.replaced }
    store.redo()
    #expect(store.project == original && !store.canUndo && store.canRedo && publications == 2)
    store.validateDocumentChange = nil
    store.redo()
    #expect(store.project == edited && store.canUndo && !store.canRedo && publications == 3)
}
