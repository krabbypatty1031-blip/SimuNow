import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

/// Canned L2 client so the store logic can be tested without OpenFOAM.
/// The recorded snapshot and fidelity prove the store passes the right wire form.
actor RecordingL2Client: L2TaskClient {
    nonisolated let isConfigured: Bool
    var nextState: RunState = .succeeded
    var cannedResult: SimulationResult?
    var cannedSlice: FieldSlice?
    var cannedFlow: FlowOverlay?
    var cancelled = Set<UUID>()
    var lastSnapshot: Data?
    var servedIdentity: RunIdentity?

    init(isConfigured: Bool = true) {
        self.isConfigured = isConfigured
    }

    func submitL2(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt {
        lastSnapshot = snapshot
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

    func loadFieldSlice(runID: UUID) async throws -> FieldSlice? {
        cannedSlice
    }

    func loadFlowOverlay(runID: UUID) async throws -> FlowOverlay? {
        cannedFlow
    }

    func loadEvents(runID: UUID) async throws -> [SimulationEvent] {
        []
    }

    func prepare(
        result: SimulationResult,
        state: RunState = .succeeded,
        slice: FieldSlice? = nil,
        flow: FlowOverlay? = nil
    ) {
        cannedResult = result
        nextState = state
        cannedSlice = slice
        cannedFlow = flow
    }
}

@MainActor
@Test func unconfiguredStoreCannotSubmitL2() async {
    let store = WorkspaceStore()
    store.loadOfficeTemplate()
    #expect(store.isPhysicalModelComplete)
    #expect(!store.canSubmitL2)
    await store.submitL2()
    #expect(store.activeRun == nil)
    #expect(store.lastResult == nil)
    #expect(store.lastFieldSlice == nil)
    #expect(store.lastFlowOverlay == nil)
    #expect(store.project?.occupancy?.occupantCount.value == 8)
}

@MainActor
@Test func configuredStoreSubmitsL2LoadsSliceAndMarksStaleAfterEdit() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let result = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false),
            ResultMetric(
                name: "seat_pmv_min",
                value: nil,
                unit: "PMV",
                method: "iso7730_pmv",
                fidelity: .l2,
                omitted: true,
                reason: "not evaluable: missing mrtC, rhPct, clo, met (comfort inputs not modeled)"
            )
        ],
        supplyTemperatureC: 16,
        setpointC: 26
    )
    let slice = FieldSlice(
        zM: 1.1,
        originM: FieldSlice.SliceOrigin(x: 0.1, y: 0.1),
        spacingM: FieldSlice.SliceOrigin(x: 0.25, y: 0.25),
        shape: FieldSlice.SliceShape(nx: 2, ny: 2),
        values: [[25.0, 25.1], [25.2, 25.3]],
        valid: [[true, true], [true, true]],
        stats: FieldSlice.SliceStats(validCount: 4, minC: 25.0, maxC: 25.3),
        inputHash: "pending"
    )
    let flow = FlowOverlay(
        zM: 1.1,
        glyphs: [
            FlowOverlay.Glyph(x: 1.5, y: 1.5, z: 1.1, ux: 0.2, uy: 0, uz: 0, mag: 0.2)
        ],
        lines: [
            FlowOverlay.Streamline(
                id: "SL1",
                points: [
                    FlowOverlay.StreamlinePoint(x: 0.2, y: 3, z: 1.1, mag: 0.2),
                    FlowOverlay.StreamlinePoint(x: 1.4, y: 3, z: 1.1, mag: 0.18)
                ]
            )
        ],
        stats: FlowOverlay.FlowStats(glyphCount: 1, lineCount: 1, minMag: 0.18, maxMag: 0.2),
        inputHash: "pending"
    )
    let client = RecordingL2Client()
    await client.prepare(result: result, slice: slice, flow: flow)
    let store = WorkspaceStore(l2Client: client)
    store.loadOfficeTemplate()
    #expect(store.canSubmitL2)
    await store.submitL2()
    #expect(store.activeRun?.state == .succeeded)
    #expect(store.lastResult?.metric(named: "seat_t_c_min")?.value == 25.08)
    #expect(store.lastResult?.metric(named: "seat_pmv_min")?.omitted == true)
    #expect(store.lastFieldSlice?.zM == 1.1)
    #expect(store.lastFieldSlice?.stats.maxC == 25.3)
    #expect(store.lastFlowOverlay?.glyphs.count == 1)
    #expect(store.resultFreshness == .current)
    store.applyOccupantCount(10)
    #expect(store.resultFreshness == .stale)
}

/// L2 must not wipe the last L1 cooling and electric power on the same project.
@MainActor
@Test func submitL2LeavesPreviousL1WattsInPlace() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let l1 = try L1Accounting.evaluate(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        draft: draft,
        context: L1DayContext(weatherPath: "weather/HK.epw", weatherHash: "h", coolingLoadW: 6000)
    )
    let l2 = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ]
    )
    let l1Client = RecordingL1Client()
    await l1Client.prepare(result: l1)
    let l2Client = RecordingL2Client()
    await l2Client.prepare(result: l2)
    let store = WorkspaceStore(l1Client: l1Client, l2Client: l2Client)
    store.loadOfficeTemplate()
    await store.submitL1()
    await store.submitL2()
    #expect(store.lastL1Result?.metric(named: "q_cool_w")?.value == 6000)
    #expect(store.lastL1Result?.metric(named: "p_elec_w")?.value == 2000)
    #expect(store.lastL2Result?.metric(named: "seat_t_c_min")?.value == 25.08)
    let snapshot = try #require(await l2Client.lastSnapshot)
    let object = try #require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
    #expect(object["_l1Result"] != nil)
    store.applyOccupantCount(10)
    await store.submitL2()
    let staleSnapshot = try #require(await l2Client.lastSnapshot)
    let staleObject = try #require(JSONSerialization.jsonObject(with: staleSnapshot) as? [String: Any])
    #expect(staleObject["_l1Result"] == nil)
}

@MainActor
@Test func failedL2RunKeepsSeatMetricsOmittedAndLoadsNoSlice() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    var failed = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "pending"),
        state: .failed,
        quality: .notEvaluated,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: nil, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: true)
        ],
        supplyTemperatureC: 16,
        setpointC: 26
    )
    failed.state = .failed
    let client = RecordingL2Client()
    await client.prepare(result: failed, state: .failed)
    let store = WorkspaceStore(l2Client: client)
    store.loadOfficeTemplate()
    await store.submitL2()
    #expect(store.activeRun?.state == .failed)
    #expect(store.lastResult?.metric(named: "seat_t_c_min")?.omitted == true)
    #expect(store.lastResult?.metric(named: "seat_t_c_min")?.value == nil)
    // Quality failed runs write no slice or flow; the store must not display one.
    #expect(store.lastFieldSlice == nil)
    #expect(store.lastFlowOverlay == nil)
    #expect(store.project?.occupancy?.occupantCount.value == 8)
}
