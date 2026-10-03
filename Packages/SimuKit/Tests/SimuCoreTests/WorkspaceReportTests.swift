import Foundation
import Testing
import SimuCore
import SimuReporting
import SimuWorkspace
#if os(macOS)
import PDFKit
#endif

/// No pin list keeps the empty-state path: no evidence and no export control.
@MainActor
@Test func emptyCandidatesKeepReportNilAndRefuseExport() {
    let store = WorkspaceStore()
    store.loadOfficeTemplate()
    store.allowEnvironmentGenerator = false
    #expect(store.reportEvidence == nil)
    #expect(!store.canExportEvidencePDF)
    #expect(store.reportStatusLine == nil)
    #expect(!store.canSubmitL1)
    #expect(!store.canSubmitL2)
    #expect(WorkspaceStore.evidenceExportLabel == "Export comparison notes")
    #expect(WorkspaceStore.evidenceExportLabel != "生成报告")
    #expect(WorkspaceStore.evidenceExportLabel != "导出证据 PDF")
}

/// A quality-failed pin can be explained. It must not become a recommendation PDF.
@MainActor
@Test func qualityFailedOnlyExplainsAndRefusesExport() async throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let failed = reportCandidate(
        name: "质量失败",
        draft: office,
        quality: .failed,
        seatMinC: nil,
        passRatio: nil,
        passCount: nil,
        evalCount: nil,
        ratioOmitted: true
    )
    let store = WorkspaceStore()
    store.project = office
    store.candidateRuns = [failed]
    store.allowEnvironmentGenerator = false
    store.reportGenerator = StubReportGenerator()

    let evidence = try #require(store.reportEvidence)
    // ADR-021: no classifier cards any more. A single quality-failed pin
    // has no pair diff and stays on the page; export is refused.
    #expect(evidence.pairDiff == nil)
    #expect(!evidence.isComparisonReportable)
    #expect(!store.canExportEvidencePDF)
    #expect(store.reportStatusLine == WorkspaceStore.blockedExportStatus)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-blocked-\(UUID().uuidString).pdf")
    await #expect(throws: EvidencePDFError.notExportable) {
        try await store.writeEvidencePDF(to: url)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(store.reportMessage == WorkspaceStore.blockedExportStatus)
}

/// Office demo numbers stay on the cards. Missing DeepSeek hides export.
@MainActor
@Test func officeDemoWithoutDeepSeekHidesExport() async throws {
    let pair = try officeDemoPair()
    let store = WorkspaceStore()
    store.project = pair.high.draft
    store.candidateRuns = [pair.low, pair.high]
    store.allowEnvironmentGenerator = false

    #expect(pair.high.draft.occupancy?.comfort?.clo.value == 0.5)
    #expect(pair.high.draft.occupancy?.comfort?.met.value == 1.2)
    #expect(pair.high.draft.costAssumptions?.pricePerKWh == 1.2)
    #expect(pair.high.draft.costAssumptions?.reference == "比赛演示假设，非真实电价")

    let evidence = try #require(store.reportEvidence)
    #expect(evidence.isComparisonReportable)
    // The diff the AI narrates: the user lowered the supply patch and the
    // seat temperature followed. Same basis, so no mismatch sentence.
    let diff = try #require(evidence.pairDiff)
    #expect(diff.inputChanges.contains { $0.field == "supplyZ0M" })
    #expect(diff.inputChanges.contains { $0.sentence.contains("Supply-outlet lower edge from 2.10 m to 2.48 m") })
    #expect(diff.basisMismatchReason == nil)
    #expect(diff.resultDeltas.contains { $0.dimension == "energy" && $0.field == "dayCost" })
    #expect(diff.resultDeltas.contains { $0.dimension == "comfort" && $0.field == "seatTMinC" && $0.delta == 0.22 })
    #expect(!store.canExportEvidencePDF)
    #expect(store.reportStatusLine == WorkspaceStore.missingDeepSeekStatus)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-nodeepseek-\(UUID().uuidString).pdf")
    await #expect(throws: EvidencePDFError.generatorUnavailable) {
        try await store.writeEvidencePDF(to: url)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(store.reportMessage == WorkspaceStore.missingDeepSeekStatus)
}

/// Office demo numbers: comfort defaults, demo tariff, two same-basis L2 pins.
/// A configured generator writes a readable PDF plus the identity appendix.
@MainActor
@Test func officeDemoExportsDeepSeekReportWithAppendix() async throws {
    let pair = try officeDemoPair()
    let store = WorkspaceStore()
    store.project = pair.high.draft
    store.candidateRuns = [pair.low, pair.high]
    store.allowEnvironmentGenerator = false
    store.reportGenerator = StubReportGenerator()

    let evidence = try #require(store.reportEvidence)
    #expect(store.canExportEvidencePDF)
    #expect(evidence.isComparisonReportable)
    #expect(store.reportStatusLine == nil)

    #if os(macOS)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-demo-\(UUID().uuidString).pdf")
    try await store.writeEvidencePDF(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let text = try #require(PDFDocument(url: url)?.string)
    // ADR-024: WebKit extraction radicalizes 风 and inserts whitespace; use pdfTextContains.
    #expect(pdfTextContains("办公室送风对比", in: text))
    #expect(pdfTextContains("DeepSeek", in: text))
    #expect(pdfTextContains(pair.low.identity.runID.uuidString, in: text))
    #expect(pdfTextContains(pair.high.identity.runID.uuidString, in: text))
    #expect(pdfTextContains("全年电费", in: text))
    #expect(pdfTextContains("EnergyPlus", in: text))
    #expect(pdfTextContains("OpenFOAM", in: text))
    // ADR-021 appendix: the pair diff section replaces classifier cards.
    #expect(pdfTextContains("Differences between the two schemes", in: text))
    #expect(!pdfTextContains("比赛演示假设，非真实电价", in: text))
    let ratio = try #require(evidence.candidates.first { $0.runID == pair.high.identity.runID }?.seatPassRatio)
    #expect(pdfTextContains(UserFacingCopy.displayNumber(ratio), in: text))
    let cost = try #require(pair.high.dayCost.cost)
    let currency = try #require(pair.high.dayCost.currency)
    #expect(pdfTextContains(UserFacingCopy.displayNumber(cost), in: text))
    #expect(pdfTextContains(currency, in: text))
    #expect(store.reportMessage == WorkspaceStore.exportedStatus)
    #expect(store.reportStatusLine == WorkspaceStore.exportedStatus)
    #endif
}

private struct StubReportGenerator: ReportGenerator {
    func generate(_ evidence: ReportEvidence) async -> GeneratedReport? {
        let names = evidence.candidates.map(\.name).joined(separator: "、")
        let first = evidence.candidates[0]
        let ratio = first.seatPassRatio.map(UserFacingCopy.displayNumber) ?? "还没有"
        let dayCostText: String
        if let value = first.dayCost, let currency = first.currency {
            dayCostText = "\(UserFacingCopy.displayNumber(value)) \(currency)"
        } else {
            dayCostText = "还没有"
        }
        let annualText: String
        if let value = first.annualCost, let currency = first.currency {
            annualText = "\(UserFacingCopy.displayNumber(value)) \(currency)"
        } else {
            annualText = dayCostText
        }
        let cooling = first.coolingW.map(UserFacingCopy.displayNumber) ?? "还没有"
        let mean = first.indoorMeanC.map(UserFacingCopy.displayNumber)
            ?? first.seatTMinC.map(UserFacingCopy.displayNumber)
            ?? "还没有"
        return GeneratedReport(
            title: "办公室送风对比",
            summary: "这次对比了\(names)。方案一全年电费 \(annualText)。",
            sections: [
                ReportSection(
                    heading: ReportWriterSkill.planSummaryHeading,
                    body: "这次对比了\(names)。你把出风口下沿从 2.10 m 改为 2.48 m。"
                ),
                ReportSection(
                    heading: ReportWriterSkill.energyHeading,
                    body: "EnergyPlus 制冷量 \(cooling) W，全年电费 \(annualText)。"
                ),
                ReportSection(
                    heading: ReportWriterSkill.comfortHeading,
                    body: "OpenFOAM 室内温度 \(mean) °C，方案一合适的座位 \(ratio)。"
                ),
                ReportSection(
                    heading: ReportWriterSkill.adviceHeading,
                    body: "建议采用方案一。"
                ),
            ],
            caveats: ["采用低送风口。"]
        )
    }
}

private func officeDemoPair() throws -> (low: CandidateRun, high: CandidateRun) {
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
    // P4 Debug hand-test seats and the P3 L1 watts on the same occupied day.
    let low = reportCandidate(
        name: "低送风口",
        draft: lowered,
        seatMinC: 24.21,
        passRatio: 1,
        passCount: 4,
        evalCount: 4,
        watts: 1033.112
    )
    let high = reportCandidate(
        name: "默认送风口",
        draft: office,
        seatMinC: 24.43,
        passRatio: 1,
        passCount: 4,
        evalCount: 4,
        watts: 1033.112
    )
    return (low, high)
}

private func reportCandidate(
    name: String,
    draft: ProjectDraft,
    quality: QualityState = .passed,
    seatMinC: Double?,
    passRatio: Double?,
    passCount: Double?,
    evalCount: Double?,
    ratioOmitted: Bool = false,
    watts: Double? = nil
) -> CandidateRun {
    let metrics: [ResultMetric]
    if ratioOmitted || quality != .passed {
        metrics = SeatFeasibility.metrics(seats: nil, qualityPassed: false)
    } else {
        metrics = [
            ResultMetric(name: "seat_t_c_min", value: seatMinC, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: seatMinC == nil),
            ResultMetric(name: "seat_pass_ratio", value: passRatio, unit: "1", method: "l2_seat_gate", fidelity: .l2, omitted: passRatio == nil),
            ResultMetric(name: "seat_pass_count", value: passCount, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: passCount == nil),
            ResultMetric(name: "seat_eval_count", value: evalCount, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: evalCount == nil),
        ]
    }
    let dayCost: RepresentativeDayCost
    if let watts {
        dayCost = CostAccounting.representativeDay(
            electricPowerW: watts,
            occupiedStart: draft.occupancy?.schedule?.start ?? "08:00",
            occupiedEnd: draft.occupancy?.schedule?.end ?? "18:00",
            tariff: draft.costAssumptions ?? .demo
        )
    } else {
        dayCost = .omitted(reason: "无 L1，代表日电费省略")
    }
    return CandidateRun(
        name: name,
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-\(name)"),
        state: quality == .passed ? .succeeded : .failed,
        quality: quality,
        metrics: metrics,
        basis: CandidateRun.ComparisonBasis(
            occupantCount: draft.occupancy?.occupantCount.value ?? 0,
            occupiedStart: draft.occupancy?.schedule?.start ?? "08:00",
            occupiedEnd: draft.occupancy?.schedule?.end ?? "18:00",
            setpointC: draft.hvac?.setpointC.value ?? 0,
            supplyTemperatureC: draft.hvac?.supplyTemperatureC.value ?? 0
        ),
        draft: draft,
        dayCost: dayCost,
        l1Identity: watts == nil ? nil : RunIdentity(scenarioID: draft.id, inputHash: "l1-\(name)")
    )
}
