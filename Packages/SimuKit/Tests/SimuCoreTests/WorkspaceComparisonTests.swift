import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

@MainActor
@Test func pinningCurrentResultFreezesCandidateWithBasis() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let result = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-a"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
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
        inputHash: "hash-a"
    )
    let client = RecordingL2Client()
    await client.prepare(result: result, slice: slice)
    let store = WorkspaceStore(l2Client: client)
    store.loadOfficeTemplate()
    await store.submitL2()
    #expect(store.canPinCandidate)
    store.pinCurrentAsCandidate(named: "基准")
    #expect(store.candidateRuns.count == 1)
    // Basis mirrors the run's own scope: office template people, hours, setpoints.
    #expect(store.candidateRuns[0].basis.occupantCount == 8)
    #expect(store.candidateRuns[0].basis.setpointC == 26)
    #expect(store.candidateRuns[0].basis.supplyTemperatureC == 16)
    #expect(store.candidateRuns[0].slice?.stats.maxC == 25.3)

    // Later edits do not mutate the pinned record; only the project moves on.
    store.applyOccupantCount(10)
    #expect(store.candidateRuns[0].basis.occupantCount == 8)
    // The frozen geometry snapshot also stays at the pinned room size.
    #expect(store.candidateRuns[0].draft.geometry?.sizeX.value == 6)
    #expect(store.candidateFreshness(store.candidateRuns[0]) == .stale)
}

@MainActor
@Test func candidateFreshnessIsCurrentWhileDraftMatchesRun() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let result = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-a"),
        state: .failed,
        quality: .failed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: nil, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: true)
        ],
        supplyTemperatureC: 16,
        setpointC: 26
    )
    let client = RecordingL2Client()
    await client.prepare(result: result, state: .failed)
    let store = WorkspaceStore(l2Client: client)
    store.loadOfficeTemplate()
    await store.submitL2()
    // A finished run with matching input pins even when quality failed; the
    // record keeps quality separate from freshness.
    store.pinCurrentAsCandidate(named: "质量失败")
    #expect(store.candidateRuns.count == 1)
    #expect(store.candidateRuns[0].quality == .failed)
    #expect(store.candidateRuns[0].slice == nil)
    #expect(store.candidateFreshness(store.candidateRuns[0]) == .current)
}

/// A stale result belongs to an older input; pinning it would label the
/// current draft with someone else's numbers. The store must refuse.
@MainActor
@Test func staleResultRefusesToPin() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let result = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-a"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ],
        supplyTemperatureC: 16,
        setpointC: 26
    )
    let client = RecordingL2Client()
    await client.prepare(result: result)
    let store = WorkspaceStore(l2Client: client)
    store.loadOfficeTemplate()
    await store.submitL2()
    store.applyOccupantCount(10)
    #expect(store.resultFreshness == .stale)
    #expect(!store.canPinCandidate)
    store.pinCurrentAsCandidate()
    #expect(store.candidateRuns.isEmpty)
}

/// The comparison page must share one physical colour range instead of
/// renormalising each candidate to hide differences.
@MainActor
@Test func comparisonPaletteSpansAllQualityPassedSlices() async throws {
    func slice(minC: Double, maxC: Double) -> FieldSlice {
        FieldSlice(
            zM: 1.1,
            originM: FieldSlice.SliceOrigin(x: 0.1, y: 0.1),
            spacingM: FieldSlice.SliceOrigin(x: 0.25, y: 0.25),
            shape: FieldSlice.SliceShape(nx: 1, ny: 1),
            values: [[minC]],
            valid: [[true]],
            stats: FieldSlice.SliceStats(validCount: 1, minC: minC, maxC: maxC),
            inputHash: "h"
        )
    }

    let draft = try ProjectTemplates.bundled(named: "office").project
    func makeResult(_ i: Int) -> SimulationResult {
        SimulationResult(
            identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-\(i)"),
            state: .succeeded,
            quality: .passed,
            metrics: [
                ResultMetric(name: "seat_t_c_min", value: 25, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
            ],
            supplyTemperatureC: 16,
            setpointC: 26
        )
    }

    // Candidate A: 24.0 - 25.0 C; candidate B: 24.5 - 26.0 C.
    let a = RecordingL2Client()
    await a.prepare(result: makeResult(0), slice: slice(minC: 24.0, maxC: 25.0))
    let storeA = WorkspaceStore(l2Client: a)
    storeA.loadOfficeTemplate()
    await storeA.submitL2()
    storeA.pinCurrentAsCandidate(named: "基准")

    let b = RecordingL2Client()
    await b.prepare(result: makeResult(1), slice: slice(minC: 24.5, maxC: 26.0))
    let storeB = WorkspaceStore(l2Client: b)
    storeB.loadOfficeTemplate()
    // Different room length: geometry is the comparison axis, the basis stays.
    storeB.applyRoomSize(x: 7, y: 6, z: 2.8)
    await storeB.submitL2()
    storeB.pinCurrentAsCandidate(named: "加长")

    // One store must show them together; move B's record into A's store.
    storeA.candidateRuns.append(contentsOf: storeB.candidateRuns)
    let range = storeA.comparisonPaletteRange
    // Joint span of both passed slices, not each field's own rainbow.
    #expect(range?.minC == 24.0)
    #expect(range?.maxC == 26.0)
    #expect(storeA.candidatesShareBasis == true)
}

@MainActor
@Test func mixedBasisCandidatesAreFlaggedNotCompared() async throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let result = SimulationResult(
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-a"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ],
        supplyTemperatureC: 16,
        setpointC: 26
    )
    let client = RecordingL2Client()
    await client.prepare(result: result)
    let store = WorkspaceStore(l2Client: client)
    store.loadOfficeTemplate()
    await store.submitL2()
    store.pinCurrentAsCandidate(named: "基准")
    store.applyOccupantCount(12)
    await store.submitL2()
    store.pinCurrentAsCandidate(named: "多人")
    #expect(store.candidateRuns.count == 2)
    #expect(store.candidatesShareBasis == false)
    #expect(store.basisMismatchText?.contains("人数") == true)
}
