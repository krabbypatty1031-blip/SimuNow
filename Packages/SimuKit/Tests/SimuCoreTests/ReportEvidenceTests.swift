import Foundation
import Testing
import SimuCore
import SimuReporting
import SimuWorkspace
#if os(macOS)
import PDFKit
#endif

/// Evidence is a frozen copy of pinned runs. Required schema keys survive a round trip,
/// and the pass ratio / day cost are the candidate's numbers.
@Test func reportEvidenceRoundTripsAndKeepsCandidateNumbers() throws {
    let pair = try evidencePair()
    let evidence = ReportEvidence.build(from: [pair.low, pair.high])
    let decoded = try JSONDecoder().decode(ReportEvidence.self, from: JSONEncoder().encode(evidence))
    #expect(decoded == evidence)

    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any]
    let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: reportEvidenceSchemaURL())) as? [String: Any]
    let required = try #require(schema?["required"] as? [String])
    for key in required {
        #expect(object?[key] != nil)
    }
    #expect(evidence.schemaVersion == 1)
    #expect(evidence.tariffReference == "比赛演示假设，非真实电价")
    #expect(!evidence.comfortAssumptions.isEmpty)

    let low = try #require(evidence.candidates.first { $0.runID == pair.low.identity.runID })
    #expect(low.inputHash == pair.low.identity.inputHash)
    #expect(low.quality == .passed)
    #expect(low.seatPassRatio == 1)
    #expect(low.seatPassRatioOmitted == false)
    #expect(low.dayEnergyKWh == pair.low.dayCost.energyKWh)
    #expect(low.dayCost == pair.low.dayCost.cost)
    #expect(low.currency == pair.low.dayCost.currency)
    #expect(low.l1RunID == pair.low.l1Identity?.runID)
    #expect(low.seatBandLowC == SeatFeasibility.airLowC)
    #expect(low.seatBandHighC == SeatFeasibility.airHighC)

    let encoded = try JSONEncoder().encode(evidence)
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(!text.contains("payback"))
    #expect(!text.contains("annual_kwh"))
    #expect(!text.contains("满意率"))
}

/// Editing the live draft after the evidence object exists must not retarget run IDs.
@MainActor
@Test func editingLiveDraftLeavesCitedRunIDsFrozen() throws {
    let pair = try evidencePair()
    let store = WorkspaceStore()
    store.project = pair.high.draft
    store.candidateRuns = [pair.low, pair.high]
    let built = try #require(store.reportEvidence)
    let runIDs = built.candidates.map(\.runID)
    let hashes = built.candidates.map(\.inputHash)
    let cardIDs = built.cards.flatMap(\.citedRunIDs)

    store.project?.name = "正在编辑的草稿"
    store.project?.hvac?.setpointC.value = 21
    store.project?.hvac?.supply.z0.value = 0.2

    #expect(built.candidates.map(\.runID) == runIDs)
    #expect(built.candidates.map(\.inputHash) == hashes)
    #expect(built.cards.flatMap(\.citedRunIDs) == cardIDs)
    let again = try #require(store.reportEvidence)
    #expect(again.candidates.map(\.runID) == runIDs)
    #expect(again.candidates.map(\.inputHash) == hashes)
    #expect(again.candidates.map(\.supplyZ0M) == built.candidates.map(\.supplyZ0M))
}

#if os(macOS)
/// Tables and assumptions come from the evidence object. A nil narrator still writes a PDF.
@Test func evidencePDFWithoutNarratorContainsTableAndAssumptions() throws {
    let pair = try evidencePair()
    let evidence = ReportEvidence.build(from: [pair.low, pair.high])
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-evidence-\(UUID().uuidString).pdf")
    try EvidencePDFAssembler.write(evidence: evidence, narration: nil, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let text = try #require(PDFDocument(url: url)?.string)
    #expect(text.contains("对比说明"))
    #expect(text.contains(pair.low.name))
    #expect(text.contains(pair.high.name))
    #expect(text.contains("详细编号"))
    let body = String(text.split(separator: "详细编号", maxSplits: 1).first ?? "")
    #expect(!body.contains("inputHash"))
    #expect(!body.contains(pair.high.identity.inputHash))
    #expect(!body.contains("mrtC"))
    #expect(text.contains(pair.low.identity.runID.uuidString))
    #expect(text.contains(pair.high.identity.inputHash))
    #expect(text.contains(UserFacingCopy.qualityTitle(pair.low.quality)))
    #expect(text.contains("比赛演示假设，非真实电价"))
    #expect(text.contains("23"))
    #expect(text.contains("26"))
    #expect(text.contains("周围表面温度"))
    let ratio = try #require(evidence.candidates.first { $0.runID == pair.high.identity.runID }?.seatPassRatio)
    #expect(text.contains(UserFacingCopy.displayNumber(ratio)))
    let assumption = try #require(evidence.comfortAssumptions.first?.reference)
    #expect(text.contains(assumption))
    #expect(!text.contains("叙述未采用"))
}
#endif

private func evidencePair() throws -> (low: CandidateRun, high: CandidateRun) {
    let office = try ProjectTemplates.bundled(named: "office").project
    var lowered = office
    let supply = try #require(office.hvac?.supply)
    _ = lowered.applySupplyTerminal(
        wall: supply.wall,
        s0: supply.s0.value,
        s1: supply.s1.value,
        z0: 2.10,
        z1: 2.28,
        source: .user
    )
    let low = evidenceCandidate(name: "低送风口", draft: lowered, seatMinC: 24.21, passRatio: 1, watts: 1000)
    let high = evidenceCandidate(name: "默认送风口", draft: office, seatMinC: 24.43, passRatio: 0.75, watts: 1500)
    return (low, high)
}

private func evidenceCandidate(
    name: String,
    draft: ProjectDraft,
    seatMinC: Double,
    passRatio: Double,
    watts: Double
) -> CandidateRun {
    let passCount = passRatio == 1 ? 8.0 : 6.0
    return CandidateRun(
        name: name,
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-\(name)"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: seatMinC, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_ratio", value: passRatio, unit: "1", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_count", value: passCount, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_eval_count", value: 8, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: false),
        ],
        basis: CandidateRun.ComparisonBasis(
            occupantCount: draft.occupancy?.occupantCount.value ?? 0,
            occupiedStart: draft.occupancy?.schedule?.start ?? "08:00",
            occupiedEnd: draft.occupancy?.schedule?.end ?? "18:00",
            setpointC: draft.hvac?.setpointC.value ?? 0,
            supplyTemperatureC: draft.hvac?.supplyTemperatureC.value ?? 0
        ),
        draft: draft,
        dayCost: CostAccounting.representativeDay(
            electricPowerW: watts,
            occupiedStart: draft.occupancy?.schedule?.start ?? "08:00",
            occupiedEnd: draft.occupancy?.schedule?.end ?? "18:00",
            tariff: draft.costAssumptions ?? .demo
        ),
        l1Identity: RunIdentity(scenarioID: draft.id, inputHash: "l1-\(name)")
    )
}

private func reportEvidenceSchemaURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Protocols/Schemas/report-evidence.schema.json")
}
