import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

actor RecordingL1Client: L1TaskClient {
    nonisolated let isConfigured: Bool
    var nextState: RunState = .succeeded
    var cannedResult: SimulationResult?
    var cannedEvents: [SimulationEvent] = []
    var delayNanoseconds: UInt64 = 0
    var cancelled = Set<UUID>()
    var lastSnapshot: Data?
    var servedIdentity: RunIdentity?

    init(isConfigured: Bool = true) {
        self.isConfigured = isConfigured
    }

    func submitL1(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt {
        lastSnapshot = snapshot
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        servedIdentity = request.identity
        if cancelled.contains(request.identity.runID) {
            return RunReceipt(identity: request.identity, state: .cancelled)
        }
        return RunReceipt(identity: request.identity, state: nextState)
    }

    func cancel(runID: UUID) async throws {
        cancelled.insert(runID)
    }

    func loadResult(runID: UUID) async throws -> SimulationResult? {
        guard var result = cannedResult else { return nil }
        if let servedIdentity {
            result.identity = servedIdentity
        }
        return result
    }

    func loadEvents(runID: UUID) async throws -> [SimulationEvent] {
        cannedEvents
    }
}

@MainActor
@Test func unconfiguredStoreCannotSubmitL1() async {
    let store = WorkspaceStore()
    store.loadOfficeTemplate()
    #expect(store.isPhysicalModelComplete)
    #expect(!store.canSubmitL1)
    await store.submitL1()
    #expect(store.activeRun == nil)
    #expect(store.lastResult == nil)
    #expect(store.project?.occupancy?.occupantCount.value == 8)
}

@MainActor
@Test func configuredStoreSubmitsMetricsAndMarksStaleAfterHeadcountEdit() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let result = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let client = RecordingL1Client()
    await client.prepare(result: result, events: [
        SimulationEvent(
            runID: result.identity.runID,
            scenarioID: draft.id,
            inputHash: "pending",
            sequence: 0,
            timestamp: "2026-10-03T00:00:00Z",
            eventType: .completed,
            stage: .succeeded,
            payload: SimulationEventPayload(message: "l1 completed")
        )
    ])
    let store = WorkspaceStore(l1Client: client)
    store.loadOfficeTemplate()
    #expect(store.canSubmitL1)
    await store.submitL1()
    #expect(store.activeRun?.state == .succeeded)
    #expect(store.lastResult?.metric(named: "q_cool_w")?.value == 6000)
    #expect(store.lastResult?.metric(named: "p_elec_w")?.value == 2000)
    #expect(store.lastResult?.metric(named: "annual_kwh")?.omitted == true)
    #expect(store.metricText(named: "annual_kwh") == "未知")
    #expect(store.lastBoundary?.supplyTemperatureC == 16)
    #expect(store.lastBoundary?.setpointC == 26)
    #expect(store.lastBoundary?.returnTerminal.id == "RET1")
    #expect(store.resultFreshness == .current)
    store.applyOccupantCount(10)
    #expect(store.project?.occupancy?.occupantCount.value == 10)
    #expect(store.resultFreshness == .stale)
}

@MainActor
@Test func failedSubmitDoesNotChangeOccupantCountOrInventWatts() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    var failed = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: nil, weatherHash: nil, coolingLoadW: nil)
    )
    failed.state = .failed
    let client = RecordingL1Client()
    await client.prepare(result: failed, state: .failed)
    let store = WorkspaceStore(l1Client: client)
    store.loadOfficeTemplate()
    store.applyOccupantCount(9)
    await store.submitL1()
    #expect(store.activeRun?.state == .failed)
    #expect(store.project?.occupancy?.occupantCount.value == 9)
    #expect(store.project?.geometry?.sizeX.value == 6)
    #expect(store.lastResult?.metric(named: "q_cool_w")?.omitted == true)
    #expect(store.lastResult?.metric(named: "q_cool_w")?.value == nil)
}

@MainActor
@Test func cancelKeepsCurrentProject() async {
    let client = RecordingL1Client()
    await client.setDelay(400_000_000)
    let store = WorkspaceStore(l1Client: client)
    store.loadOfficeTemplate()
    store.applyOccupantCount(11)
    async let submitted: Void = store.submitL1()
    try? await Task.sleep(for: .milliseconds(40))
    await store.cancelActiveRun()
    await submitted
    #expect(store.project?.occupancy?.occupantCount.value == 11)
    #expect(store.activeRun?.state == .cancelled || store.activeRun?.state == .succeeded)
}

#if os(macOS)
@MainActor
@Test func applyLocalEngineWithPinnedPathsEnablesSubmitWithoutHardcodedDesktop() {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let engines = repo.appendingPathComponent("test/engines")
    guard LocalEngineProbe.isConfigured(repositoryRoot: repo, enginesRoot: engines) else {
        return
    }
    let store = WorkspaceStore()
    store.loadOfficeTemplate()
    #expect(!store.canSubmitL1)
    store.applyLocalEngine(repositoryRoot: repo, enginesRoot: engines)
    #expect(store.l1Client.isConfigured)
    #expect(store.canSubmitL1)
    #expect(!store.engineStatus.contains("/Users/"))
}
#endif

extension RecordingL1Client {
    func prepare(result: SimulationResult, state: RunState = .succeeded, events: [SimulationEvent] = []) {
        cannedResult = result
        nextState = state
        cannedEvents = events
    }

    func setDelay(_ nanoseconds: UInt64) {
        delayNanoseconds = nanoseconds
    }
}
