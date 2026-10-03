import Foundation
import os
import Testing
import SimuCore
import SimuReporting
#if os(macOS)
import PDFKit
#endif

/// No key means no narration. The evidence PDF is still written.
@Test func missingAPIKeyReturnsNilAndPDFStillWrites() async throws {
    let evidence = try narratorEvidence()
    let probe = Probe()
    let narrator = OpenAICompatibleNarrator(
        baseURL: URL(string: "https://example.invalid")!,
        keyProvider: { nil },
        transport: { _ in
            await probe.mark()
            throw URLError(.cancelled)
        }
    )
    let narration = await narrator.narrate(evidence)
    #expect(narration == nil)
    #expect(await probe.wasCalled() == false)

    #if os(macOS)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-nokey-\(UUID().uuidString).pdf")
    try EvidencePDFAssembler.write(evidence: evidence, narration: narration, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let text = try #require(PDFDocument(url: url)?.string)
    #expect(text.contains(evidence.tariffReference))
    #expect(text.contains(evidence.candidates[0].runID.uuidString))
    #endif
}

/// A paragraph that introduces 37 is dropped. A paragraph that only repeats listed figures stays.
@Test func proseWithUnlisted37PercentIsRejected() throws {
    let evidence = try narratorEvidence()
    let encoded = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
    #expect(!encoded.contains("37"))
    let listed = String(format: "%g", evidence.candidates[0].seatBandLowC)
    let prefix = String(evidence.candidates[0].runID.uuidString.prefix(8))
    let narration = ReportNarration(
        headline: "送风高度不同",
        cardProse: [
            "comfort": "座位带下限 \(listed) °C，见证据表。",
            "run": "引用 \(prefix)。",
            "bad": "相对基准节电 37%。",
        ],
        caveats: ["稳态场不表示开机降温时间。"]
    )
    let filtered = NarrationGuard.filter(narration, evidence: evidence)
    #expect(filtered.cardProse["bad"] == "叙述未采用（含证据外数字）")
    #expect(filtered.cardProse["comfort"] == narration.cardProse["comfort"])
    #expect(filtered.cardProse["run"] == narration.cardProse["run"])
    #expect(filtered.headline == narration.headline)
    #expect(filtered.caveats == narration.caveats)

    #if os(macOS)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-guard-\(UUID().uuidString).pdf")
    try EvidencePDFAssembler.write(evidence: evidence, narration: narration, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let text = try #require(PDFDocument(url: url)?.string)
    #expect(text.contains("叙述未采用（含证据外数字）"))
    #expect(!text.contains("37"))
    #expect(text.contains(evidence.candidates[0].runID.uuidString))
    #endif
}

/// The API key stays out of the PDF, the project JSON, and narrator logs.
@Test func apiKeyDoesNotLeakIntoPDFProjectOrLog() async throws {
    let secret = "sk-test-simunow-not-a-real-key"
    let evidence = try narratorEvidence()
    let lines = OSAllocatedUnfairLock(initialState: [String]())
    let requests = OSAllocatedUnfairLock(initialState: [URLRequest]())
    let narrator = OpenAICompatibleNarrator(
        baseURL: URL(string: "https://reports.example.invalid/base")!,
        keyProvider: { secret },
        log: { line in lines.withLock { $0.append(line) } },
        transport: { request in
            requests.withLock { $0.append(request) }
            throw URLError(.cannotConnectToHost)
        }
    )
    let narration = await narrator.narrate(evidence)
    #expect(narration == nil)
    let path = requests.withLock { $0.first?.url?.path }
    #expect(path == "/base/v1/chat/completions")
    let logText = lines.withLock { $0.joined(separator: "\n") }
    #expect(!logText.contains(secret))

    let projectJSON = String(decoding: try JSONEncoder().encode(try officeDraft()), as: UTF8.self)
    let evidenceJSON = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
    #expect(!projectJSON.contains(secret))
    #expect(!evidenceJSON.contains(secret))

    #if os(macOS)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-key-\(UUID().uuidString).pdf")
    try EvidencePDFAssembler.write(evidence: evidence, narration: narration, to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = try Data(contentsOf: url)
    #expect(bytes.range(of: Data(secret.utf8)) == nil)
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
