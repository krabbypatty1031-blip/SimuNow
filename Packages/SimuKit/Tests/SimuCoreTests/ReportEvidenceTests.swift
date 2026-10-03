import Foundation
import Testing
import SimuCore
import SimuReporting
import SimuWorkspace
#if os(macOS)
import PDFKit
#endif

#if os(macOS)
/// WebKit's PDF text layer extracts CJK glyphs as separate runs with inserted
/// whitespace, and emits some Han characters as radical code points. Kangxi
/// radicals (⼝⽐⽅⽤) recover through NFKC compatibility mapping, but CJK
/// Radicals Supplement (风→⻛ U+2EDB) has no decomposition in Unicode, so
/// the observed look-alikes are mapped back by hand. Visual rendering is
/// unaffected; this only repairs extracted text for contains() assertions.
private let webKitRadicalLookalikes: [Character: Character] = [
    "⻛": "风", "⻜": "飞", "⻝": "食", "⻢": "马", "⻦": "鸟", "⻩": "黄",
    "⻪": "黾", "⻫": "齐", "⻭": "齿", "⻯": "龟", "⻰": "龙", "⻳": "龟",
    "⻋": "车", "⻅": "见", "⻉": "贝", "⻓": "长", "⻔": "门", "⻚": "页",
    "⻧": "卤", "⻨": "麦", "⻮": "齿", "⻬": "齐", "⻲": "龟",
]

func normalizedPDFText(_ text: String) -> String {
    let mapped = String(text.map { webKitRadicalLookalikes[$0] ?? $0 })
    return mapped.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
}

func pdfTextContains(_ needle: String, in haystack: String) -> Bool {
    normalizedPDFText(haystack).contains(normalizedPDFText(needle))
}
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
    #expect(low.windowCount == 1)
    #expect(low.windowAreaM2 == pair.low.draft.geometry?.openings.first(where: { $0.kind == .window })?.patchAreaM2)
    #expect(low.coolingW == 3000)
    #expect(low.electricPowerW == 1000)
    #expect(low.indoorMeanC == 24.5)
    #expect(low.indoorMinC == 24.0)
    #expect(low.indoorMaxC == 25.0)
    #expect(low.flowMinMps == 0.02)
    #expect(low.flowMaxMps == 0.04)
    #expect(low.annualEnergyKWh == CostAccounting.annualEnergyKWh(from: pair.low.dayCost.energyKWh))
    #expect(low.annualCost == CostAccounting.annualCost(from: pair.low.dayCost.cost))
    #expect(low.occupiedDaysPerYear == 365)
    #expect(low.pricePerKWh == 1.2)

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
    // ADR-021: cited IDs come from candidates plus L1 identities, no classifier cards.
    let citedIDs = built.citedRunIDs

    store.project?.name = "正在编辑的草稿"
    store.project?.hvac?.setpointC.value = 21
    store.project?.hvac?.supply.z0.value = 0.2

    #expect(built.candidates.map(\.runID) == runIDs)
    #expect(built.candidates.map(\.inputHash) == hashes)
    #expect(built.citedRunIDs == citedIDs)
    let again = try #require(store.reportEvidence)
    #expect(again.candidates.map(\.runID) == runIDs)
    #expect(again.candidates.map(\.inputHash) == hashes)
    #expect(again.candidates.map(\.supplyZ0M) == built.candidates.map(\.supplyZ0M))
}

#if os(macOS)
/// DeepSeek body plus a local appendix. Hashes stay behind 详细编号.
/// ADR-024: the PDF is HTML/CSS laid out by WebKit, so text assertions go
/// through pdfTextContains (extraction inserts whitespace / radical forms).
@Test func evidencePDFKeepsAppendixAndHidesHashesFromTheBody() async throws {
    let pair = try evidencePair()
    let evidence = ReportEvidence.build(from: [pair.low, pair.high])
    let report = GeneratedReport(
        title: "办公室送风对比",
        summary: "这次对比了\(pair.low.name)和\(pair.high.name)。",
        sections: [
            ReportSection(
                heading: ReportWriterSkill.comfortHeading,
                body: "方案一合适的座位 \(UserFacingCopy.displayNumber(1))。"
            ),
        ],
        caveats: ["采用低送风口。"]
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-evidence-\(UUID().uuidString).pdf")
    try await EvidencePDFAssembler.write(evidence: evidence, report: report, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let text = try #require(PDFDocument(url: url)?.string)
    #expect(pdfTextContains("办公室送风对比", in: text))
    #expect(pdfTextContains("DeepSeek", in: text))
    #expect(pdfTextContains(pair.low.name, in: text))
    #expect(pdfTextContains(pair.high.name, in: text))
    #expect(pdfTextContains("Calculation basis", in: text))
    #expect(pdfTextContains("Detailed IDs", in: text))
    // Whitespace-removed split: the body is everything before the detailed IDs block.
    let normalized = normalizedPDFText(text)
    let body = String(normalized.split(separator: "DetailedIDs", maxSplits: 1).first ?? "")
    #expect(!body.contains("inputHash"))
    #expect(!body.contains(pair.high.identity.inputHash))
    #expect(!body.contains("mrtC"))
    #expect(pdfTextContains(pair.low.identity.runID.uuidString, in: text))
    #expect(pdfTextContains(pair.high.identity.inputHash, in: text))
    #expect(pdfTextContains(UserFacingCopy.qualityTitle(pair.low.quality), in: text))
    #expect(pdfTextContains("Yearly electricity cost", in: text))
    #expect(pdfTextContains("Electricity price", in: text))
    #expect(!normalized.contains("比赛演示假设，非真实电价"))
    #expect(!normalized.contains("不是问卷"))
    #expect(pdfTextContains("23", in: text))
    #expect(pdfTextContains("26", in: text))
    #expect(pdfTextContains("Surrounding surface temperature", in: text))
    let ratio = try #require(evidence.candidates.first { $0.runID == pair.high.identity.runID }?.seatPassRatio)
    #expect(pdfTextContains(UserFacingCopy.displayNumber(ratio), in: text))
    let assumption = try #require(evidence.comfortAssumptions.first?.reference)
    #expect(assumption == UserFacingCopy.storedMRTEqualsSetpoint)
    #expect(pdfTextContains(UserFacingCopy.english.displayStoredNote(assumption), in: text))
    #expect(!pdfTextContains(UserFacingCopy.storedMRTEqualsSetpoint, in: text))
    #expect(!pdfTextContains("叙述未采用", in: text))
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
            ResultMetric(name: "seat_t_c_max", value: seatMinC + 0.3, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_ratio", value: passRatio, unit: "1", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_count", value: passCount, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_eval_count", value: 8, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_u_mag_max", value: 0.03, unit: "m/s", method: "steady_cfd", fidelity: .l2, omitted: false),
            ResultMetric(name: "q_cool_w", value: watts * 3, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
            ResultMetric(name: "p_elec_w", value: watts, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
        ],
        slice: reportSlice(),
        flow: reportFlow(),
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

private func reportSlice() -> FieldSlice {
    FieldSlice(
        zM: 1.1,
        originM: .init(x: 0.125, y: 0.125),
        spacingM: .init(x: 0.25, y: 0.25),
        shape: .init(nx: 2, ny: 2),
        values: [[24.0, 25.0], [24.2, 24.8]],
        valid: [[true, true], [true, true]],
        stats: .init(validCount: 4, minC: 24.0, maxC: 25.0),
        inputHash: "slice-office"
    )
}

private func reportFlow() -> FlowOverlay {
    FlowOverlay(
        zM: 1.1,
        glyphs: [
            .init(x: 1, y: 1, z: 1.1, ux: 0.02, uy: 0, uz: 0, mag: 0.02),
            .init(x: 2, y: 2, z: 1.1, ux: 0.04, uy: 0, uz: 0, mag: 0.04),
        ],
        lines: [
            .init(
                id: "line-1",
                points: [
                    .init(x: 1, y: 1, z: 1.1, mag: 0.02),
                    .init(x: 2, y: 2, z: 1.1, mag: 0.04),
                ]
            ),
        ],
        stats: .init(glyphCount: 2, lineCount: 1, minMag: 0.02, maxMag: 0.04),
        inputHash: "flow-office"
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
