import Foundation
import os
import Testing
import SimuCore
import SimuReporting
#if os(macOS)
import PDFKit
#endif

/// No key means no report and no network call.
@Test func missingAPIKeyReturnsNilAndDoesNotWriteAStandIn() async throws {
    let evidence = try narratorEvidence()
    let probe = Probe()
    let client = DeepSeekReportClient(
        keyProvider: { nil },
        transport: { _ in
            await probe.mark()
            throw URLError(.cancelled)
        }
    )
    let report = await client.generate(evidence)
    #expect(report == nil)
    #expect(await probe.wasCalled() == false)
}

/// A paragraph that introduces 37 is dropped. A paragraph that only repeats listed figures stays.
@Test func proseWithUnlisted37PercentIsRejected() throws {
    let evidence = try narratorEvidence()
    let encoded = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
    #expect(!encoded.contains("37"))
    let listed = String(format: "%g", evidence.candidates[0].seatBandLowC)
    let prefix = String(evidence.candidates[0].runID.uuidString.prefix(8))
    let report = GeneratedReport(
        title: "送风高度不同",
        summary: "座位带下限 \(listed) °C，见计算依据。",
        sections: [
            ReportSection(heading: ReportWriterSkill.planSummaryHeading, body: "座位带下限 \(listed) °C，见计算依据。"),
            ReportSection(heading: "run", body: "引用 \(prefix)。"),
            ReportSection(heading: "bad", body: "相对基准节电 37%。"),
        ],
        caveats: ["稳态场不表示开机降温时间。"]
    )
    let filtered = NarrationGuard.filter(report, evidence: evidence)
    #expect(filtered.sections.first { $0.heading == NarrationGuard.rejection } == nil)
    #expect(filtered.sections.first { $0.body == "相对基准节电 37%。" } == nil)
    #expect(filtered.sections.contains { $0.body == NarrationGuard.rejection })
    #expect(filtered.sections.contains { $0.body.contains(listed) })
    #expect(filtered.sections.contains { $0.body.contains(prefix) })
    #expect(filtered.title == report.title)
    #expect(filtered.caveats == report.caveats)

    #if os(macOS)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-guard-\(UUID().uuidString).pdf")
    try EvidencePDFAssembler.write(evidence: evidence, report: report, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let text = try #require(PDFDocument(url: url)?.string)
    #expect(text.contains("叙述未采用（含证据外数字）"))
    #expect(!text.contains("37"))
    #expect(text.contains(evidence.candidates[0].runID.uuidString))
    #endif
}

/// Two-decimal display used in the UI is allowed because that is how the rest of the app writes numbers.
@Test func twoDecimalDisplayOfListedCostIsAllowed() throws {
    let evidence = try narratorEvidence()
    let cost = try #require(evidence.candidates[0].dayCost)
    let shown = UserFacingCopy.displayNumber(cost)
    #expect(shown != String(format: "%g", cost))
    let report = GeneratedReport(
        title: "这一天费用",
        summary: "这一天费用 \(shown) HKD。",
        sections: [],
        caveats: []
    )
    let filtered = NarrationGuard.filter(report, evidence: evidence)
    #expect(filtered.summary == report.summary)
}

/// Yearly totals copied onto the evidence pack may appear in the report body.
@Test func annualCostCopiedOntoEvidenceIsAllowed() throws {
    let evidence = try narratorEvidence()
    let annual = try #require(evidence.candidates[0].annualCost)
    let shown = UserFacingCopy.displayNumber(annual)
    let report = GeneratedReport(
        title: "全年电费",
        summary: "方案一全年电费 \(shown) HKD。",
        sections: [
            ReportSection(
                heading: ReportWriterSkill.energyHeading,
                body: "EnergyPlus 全年电费 \(shown) HKD。"
            ),
            ReportSection(
                heading: ReportWriterSkill.comfortHeading,
                body: "OpenFOAM 座位温度 \(UserFacingCopy.displayNumber(try #require(evidence.candidates[0].seatTMinC))) °C。"
            ),
        ],
        caveats: ["采用方案一。"]
    )
    let filtered = NarrationGuard.filter(report, evidence: evidence)
    #expect(filtered.summary == report.summary)
    #expect(filtered.sections.map(\.heading) == report.sections.map(\.heading))
}

/// The official DeepSeek path, model, and JSON object mode are used. The API key stays out of the PDF.
@Test func deepSeekRequestUsesOfficialHostAndKeepsKeyOutOfArtifacts() async throws {
    let secret = "sk-test-simunow-not-a-real-key"
    let evidence = try narratorEvidence()
    let expected = GeneratedReport(
        title: "办公室送风对比",
        summary: "这次对比了低送风口和默认送风口。",
        sections: [
            ReportSection(heading: "座位是否合适", body: "合适的座位 \(UserFacingCopy.displayNumber(1))。"),
        ],
        caveats: ["采用低送风口。"]
    )
    let lines = OSAllocatedUnfairLock(initialState: [String]())
    let requests = OSAllocatedUnfairLock(initialState: [URLRequest]())
    let client = DeepSeekReportClient(
        keyProvider: { secret },
        log: { line in lines.withLock { $0.append(line) } },
        transport: { request in
            requests.withLock { $0.append(request) }
            let payload = String(decoding: try JSONEncoder().encode(expected), as: UTF8.self)
            let envelope: [String: Any] = ["choices": [["message": ["content": payload]]]]
            let data = try JSONSerialization.data(withJSONObject: envelope)
            let response = HTTPURLResponse(
                url: request.url ?? DeepSeekReportClient.officialBaseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    )
    let report = try #require(await client.generate(evidence))
    #expect(report.title == expected.title)

    let request = try #require(requests.withLock { $0.first })
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)")
    let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
    #expect(body?["model"] as? String == "deepseek-chat")
    #expect((body?["response_format"] as? [String: Any])?["type"] as? String == "json_object")
    let messages = try #require(body?["messages"] as? [[String: Any]])
    #expect(messages.first?["content"] as? String == ReportWriterSkill.systemPrompt)
    let prompt = try #require(messages.first?["content"] as? String)
    #expect(prompt.contains(ReportWriterSkill.planSummaryHeading))
    #expect(prompt.contains(ReportWriterSkill.energyHeading))
    #expect(prompt.contains(ReportWriterSkill.comfortHeading))
    #expect(prompt.contains(ReportWriterSkill.adviceHeading))
    // ADR-021 follow-up: the model counsels the client, it does not
    // recite the evidence table. Opinion first, figures as support.
    #expect(prompt.contains("advisor"))
    #expect(prompt.contains("view and conclusion"))
    #expect(prompt.contains("what it means for the user"))
    #expect(prompt.contains("yearly electricity cost"))
    #expect(!prompt.contains("不得推算全年电费"))
    #expect(!prompt.contains("不是全年电费"))
    let chinesePrompt = ReportWriterSkill.systemPrompt(for: .chinese)
    #expect(chinesePrompt.contains("顾问"))
    #expect(chinesePrompt.contains(ReportWriterSkill.planSummaryHeading(for: .chinese)))
    let logText = lines.withLock { $0.joined(separator: "\n") }
    #expect(!logText.contains(secret))

    let projectJSON = String(decoding: try JSONEncoder().encode(try officeDraft()), as: UTF8.self)
    let evidenceJSON = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
    #expect(!projectJSON.contains(secret))
    #expect(!evidenceJSON.contains(secret))

    #if os(macOS)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-key-\(UUID().uuidString).pdf")
    try EvidencePDFAssembler.write(evidence: evidence, report: report, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = try Data(contentsOf: url)
    #expect(bytes.range(of: Data(secret.utf8)) == nil)
    let text = try #require(PDFDocument(url: url)?.string)
    #expect(text.contains("办公室送风对比"))
    #expect(text.contains("DeepSeek"))
    #expect(text.contains("Calculation basis"))
    #endif
}

private func officeDraft() throws -> ProjectDraft {
    try ProjectTemplates.bundled(named: "office").project
}

private func narratorEvidence() throws -> ReportEvidence {
    let draft = try officeDraft()
    let runA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let runB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let l1A = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let l1B = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    var lowered = draft
    let supply = try #require(draft.hvac?.supply)
    _ = lowered.applySupplyTerminal(
        wall: supply.wall,
        s0: supply.s0.value,
        s1: supply.s1.value,
        z0: 2.10,
        z1: 2.28,
        source: .user
    )
    let low = narratorCandidate(
        name: "低送风口",
        draft: lowered,
        runID: runA,
        l1: l1A,
        seatMinC: 24.21,
        passRatio: 1,
        watts: 1000
    )
    let high = narratorCandidate(
        name: "默认送风口",
        draft: draft,
        runID: runB,
        l1: l1B,
        seatMinC: 24.43,
        passRatio: 0.75,
        watts: 1500
    )
    return ReportEvidence.build(from: [low, high])
}

private func narratorCandidate(
    name: String,
    draft: ProjectDraft,
    runID: UUID,
    l1: UUID,
    seatMinC: Double,
    passRatio: Double,
    watts: Double
) -> CandidateRun {
    CandidateRun(
        name: name,
        identity: RunIdentity(runID: runID, scenarioID: draft.id, inputHash: "hash-\(name)"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: seatMinC, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_ratio", value: passRatio, unit: "1", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_count", value: passRatio == 1 ? 8 : 6, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_eval_count", value: 8, unit: "count", method: "l2_seat_gate", fidelity: .l2, omitted: false),
        ],
        basis: CandidateRun.ComparisonBasis(
            occupantCount: draft.occupancy?.occupantCount.value ?? 0,
            occupiedStart: "08:00",
            occupiedEnd: "18:00",
            setpointC: draft.hvac?.setpointC.value ?? 0,
            supplyTemperatureC: draft.hvac?.supplyTemperatureC.value ?? 0
        ),
        draft: draft,
        dayCost: CostAccounting.representativeDay(
            electricPowerW: watts,
            occupiedStart: "08:00",
            occupiedEnd: "18:00",
            tariff: draft.costAssumptions ?? .demo
        ),
        l1Identity: RunIdentity(runID: l1, scenarioID: draft.id, inputHash: "l1-\(name)")
    )
}

private actor Probe {
    private var called = false
    func mark() { called = true }
    func wasCalled() -> Bool { called }
}
