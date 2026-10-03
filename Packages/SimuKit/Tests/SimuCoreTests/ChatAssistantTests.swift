import Foundation
import os
import Testing
import SimuCore
import SimuReporting
// @testable: ChatContextBuilder is an internal SimuWorkspace type; the
// draft-summary fixture asserts its furniture line without making it public.
@testable import SimuWorkspace

/// Consult assistant (ADR-022): the DeepSeek request carries the skill
/// prompt plus the frozen context; the free-text guard keeps invented
/// figures out of the conversation; the store always answers out loud.
@MainActor
@Test func consultAssistantRoundTripsContextAndScreensReplies() async throws {
    let secret = "sk-test-simunow-not-a-real-key"
    let evidence = try chatEvidence()
    let context = ChatContext(draftSummary: "当前草稿：房间 6.00 × 5.00 × 3.00 m；8 人。", evidence: evidence)
    let history = [
        ChatTurn(role: .user, text: "全年电费怎么算的？"),
        ChatTurn(role: .assistant, text: "代表日电费乘 365。"),
        ChatTurn(role: .user, text: "方案一制冷量是多少？"),
    ]
    let requests = OSAllocatedUnfairLock(initialState: [URLRequest]())
    let client = DeepSeekChatClient(
        keyProvider: { secret },
        transport: { request in
            requests.withLock { $0.append(request) }
            let payload: [String: Any] = ["choices": [["message": ["content": "方案一制冷量 \(UserFacingCopy.displayNumber(evidence.candidates[0].coolingW ?? 0)) W。"]]]]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(
                url: request.url ?? DeepSeekChatClient.officialBaseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }
    )
    let reply = try #require(await client.respond(to: history, context: context))
    #expect(reply.contains("制冷量"))

    let request = try #require(requests.withLock { $0.first })
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)")
    let body = try #require(request.httpBody)
    // The wire keeps history and carries the skill prompt plus frozen context.
    // Evidence JSON uses each scheme's pinned name, so assert on that.
    let pair_low_name_sentinel = evidence.candidates.first?.name ?? ""
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    #expect(messages.first?["role"] as? String == "system")
    let system = try #require(messages.first?["content"] as? String)
    #expect(system.contains(ChatWriterSkill.systemPrompt))
    #expect(system.contains(ChatWriterSkill.contextHeading))
    #expect(system.contains("当前草稿：房间"))
    // Wire language is the shipped default (Chinese), so assert the frozen
    // evidence note through the constant rather than an English literal.
    #expect(system.contains(ChatWriterSkill.frozenEvidenceNote))
    #expect(system.contains(pair_low_name_sentinel))
    let roles = messages.dropFirst().compactMap { $0["role"] as? String }
    #expect(roles == ["user", "assistant", "user"])
}

/// No key: no request, no invented stand-in answer.
@Test func consultWithoutKeyReturnsNilAndCallsNothing() async throws {
    let probe = ChatProbe()
    let client = DeepSeekChatClient(
        keyProvider: { nil },
        transport: { _ in
            await probe.mark()
            throw URLError(.cancelled)
        }
    )
    let reply = await client.respond(
        to: [ChatTurn(role: .user, text: "怎么加窗？")],
        context: ChatContext(draftSummary: nil, evidence: nil)
    )
    #expect(reply == nil)
    #expect(await probe.wasCalled() == false)
}

/// The free-text guard: evidence numbers, the user's own numbers and
/// comfort-model constants pass; an invented figure rejects the reply.
@Test func consultGuardAllowsContextNumbersAndRejectsInventedOnes() throws {
    let evidence = try chatEvidence()
    let cooling = try #require(evidence.candidates[0].coolingW)
    let context = ChatContext(
        draftSummary: "当前草稿：设定温度 26.00 °C，能效比 3.00。",
        evidence: evidence
    )
    let history = [ChatTurn(role: .user, text: "COP 到 4 以上算好吗？")]

    // Evidence figure, displayed form: passes.
    let quoted = "方案一制冷量 \(UserFacingCopy.displayNumber(cooling)) W。"
    #expect(ChatGuard.screen(quoted, history: history, context: context) == quoted)
    // The draft summary's own figures: pass.
    let setpoint = "你现在的设定温度是 26.00 °C。"
    #expect(ChatGuard.screen(setpoint, history: history, context: context) == setpoint)
    // The user's own number echoed back, plus a comfort constant: passes.
    let echo = "COP 4 在常见范围；舒适带约 ±0.5。"
    #expect(ChatGuard.screen(echo, history: history, context: context) == echo)
    // Skill-stated accounting figures (365 days, 23–26 °C band, percent
    // factor) pass even without pinned evidence — a live hand-test showed
    // "how is the yearly bill calculated" being wrongly rejected.
    let bare = ChatContext(draftSummary: "当前草稿：设定温度 26.00 °C。", evidence: nil)
    let accounting = "全年电费 = 代表日电费 × 365 个占用日；座位合适带是 23 至 26 °C。"
    #expect(ChatGuard.screen(accounting, history: history, context: bare) == accounting)
    // A figure the project does not hold: the reply ships, but with the
    // transparent caution line naming the non-project figure — the soft
    // chat guard, unlike the strict PDF guard (live hand-test 2026-10-04:
    // "what is COP" answers carry industry-typical ranges).
    let invented = "换这个方案大约能省 37%。"
    #expect(ChatGuard.screen(invented, history: history, context: context) == invented + "\n\n" + ChatGuard.cautionNote)
    // Idempotent (2026-10-04 live hand-test: the client screens once, the
    // store screens again — the double append showed two identical notes):
    // screening an already-noted reply must not add a second note.
    let noted = invented + "\n\n" + ChatGuard.cautionNote
    #expect(ChatGuard.screen(noted, history: history, context: context) == noted)
}

/// The caution note is display metadata, never model history: the stored
/// turn keeps the model's own words, so the next round's model cannot copy
/// the note style into its own reply (2026-10-04 live hand-test showed the
/// model writing its own "注：…" line after seeing one in history).
@MainActor
@Test func consultStoreStripsCautionNoteFromHistoryTurn() async throws {
    let store = WorkspaceStore()
    store.chatTypingIntervalMs = 0
    store.chatAssistant = StubChatAssistant { _, _ in "大概能省 37%。" }
    await store.sendChat("能省多少？")
    let turn = try #require(store.chatTurns.last)
    #expect(turn.role == .assistant)
    // The body keeps only the model's words; the note rides the flag.
    #expect(turn.text == "大概能省 37%。")
    #expect(turn.hasCautionNote == true)
    // A clean reply: no note flag, unchanged text.
    store.chatAssistant = StubChatAssistant { _, _ in "两个方案都通过了质量检查。" }
    await store.sendChat("质量如何？")
    let clean = try #require(store.chatTurns.last)
    #expect(clean.text == "两个方案都通过了质量检查。")
    #expect(clean.hasCautionNote == false)
    // The history handed to the model never contains the note text: the
    // model cannot imitate a line it has never seen.
    for turn in store.chatTurns where turn.role == .assistant {
        #expect(turn.text.contains(ChatGuard.cautionNote) == false)
    }
}

/// Decoding turns persisted before the caution flag existed must read the
/// flag as false, not fail (tolerant decode in `ChatTurn.init(from:)`).
@Test func chatTurnDecodesWithoutCautionFlag() throws {
    let legacy = """
    {"id":"5D4C4B33-0000-0000-0000-000000000001","role":"assistant","text":"你好","sentAt":0}
    """
    let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(legacy.utf8))
    #expect(turn.text == "你好")
    #expect(turn.hasCautionNote == false)
}

/// The draft summary carries furniture the consult assistant can quote
/// (total + per-kind counts, kind order = FurnitureKind.allCases); an empty
/// room stays silent about furniture instead of saying "家具 0 件".
@Test func chatDraftSummaryCarriesFurnitureKindsAndCounts() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    #expect(ChatContextBuilder.draftSummary(for: draft)?.contains("Furniture") == false)
    // Default kind is desk; the second box names chair explicitly.
    _ = draft.upsertObstacle(
        ObstacleBox(id: "F1", origin: Position3D(x: 1, y: 1, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75))
    )
    _ = draft.upsertObstacle(
        ObstacleBox(id: "F2", origin: Position3D(x: 3, y: 1, z: 0), size: Position3D(x: 0.5, y: 0.5, z: 0.9), kind: .chair)
    )
    // draftSummary defaults to the English copy; the Chinese wording is
    // asserted on the explicit Chinese copy below.
    let summary = try #require(ChatContextBuilder.draftSummary(for: draft))
    #expect(summary.contains("Furniture 2: Desk×1, Chair×1"))
    let chineseSummary = try #require(ChatContextBuilder.draftSummary(for: draft, copy: .chinese))
    #expect(chineseSummary.contains("家具 2 件：桌子×1、椅子×1"))
}

/// The store flow: context freezes the pinned evidence, a stubbed reply
/// joins the thread, and a missing assistant still speaks a fixed note.
@MainActor
@Test func consultStoreAsksWithContextAndAlwaysAnswers() async throws {
    let store = WorkspaceStore()
    // Skip the typewriter reveal: the flow assertions care about the final
    // spoken turns, not the per-character animation.
    store.chatTypingIntervalMs = 0
    let pair = try chatPair()
    store.project = pair.high.draft
    store.candidateRuns = [pair.low, pair.high]

    let contexts = OSAllocatedUnfairLock(initialState: [ChatContext]())
    let stub = StubChatAssistant { history, context in
        contexts.withLock { $0.append(context) }
        return "两个方案都通过了质量检查。"
    }
    store.chatAssistant = stub
    await store.sendChat("这个方案靠谱吗？")
    #expect(store.chatTurns.count == 2)
    #expect(store.chatTurns.last?.role == .assistant)
    #expect(store.chatTurns.last?.text == "两个方案都通过了质量检查。")
    // The context froze the pinned evidence, not the live draft.
    let context = try #require(contexts.withLock { $0.first })
    #expect(context.evidence?.pairDiff?.firstName == pair.low.name)
    #expect(context.draftSummary?.contains("Setpoint") == true)

    // A stubbed reply with a figure the project does not hold must not
    // bypass the guard — the turn carries the note as display metadata
    // (text stays the model's own words; see the strip test above).
    store.chatAssistant = StubChatAssistant { _, _ in "大概能省 37%。" }
    await store.sendChat("能省多少？")
    #expect(store.chatTurns.last?.text == "大概能省 37%。")
    #expect(store.chatTurns.last?.hasCautionNote == true)

    // No assistant at all: a spoken note, not silence.
    store.chatAssistant = nil
    store.allowEnvironmentChatAssistant = false
    await store.sendChat("再问一次")
    #expect(store.chatTurns.last?.text == WorkspaceStore.chatMissingKeyText)
}

// MARK: - Fixtures

private struct StubChatAssistant: ChatAssistant {
    // Stored closure kept Sendable so the stub crosses isolation cleanly.
    let respondBlock: @Sendable ([ChatTurn], ChatContext) -> String?

    init(respondBlock: @escaping @Sendable ([ChatTurn], ChatContext) -> String?) {
        self.respondBlock = respondBlock
    }

    func respond(to history: [ChatTurn], context: ChatContext) async -> String? {
        respondBlock(history, context)
    }
}

private actor ChatProbe {
    private var called = false
    func mark() { called = true }
    func wasCalled() -> Bool { called }
}

private func chatEvidence() throws -> ReportEvidence {
    let pair = try chatPair()
    return ReportEvidence.build(from: [pair.low, pair.high])
}

private func chatPair() throws -> (low: CandidateRun, high: CandidateRun) {
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
    return (
        chatCandidate(name: "低送风口", draft: lowered, seatMinC: 24.21, watts: 1000),
        chatCandidate(name: "默认送风口", draft: office, seatMinC: 24.43, watts: 1500)
    )
}

private func chatCandidate(name: String, draft: ProjectDraft, seatMinC: Double, watts: Double) -> CandidateRun {
    CandidateRun(
        name: name,
        identity: RunIdentity(scenarioID: draft.id, inputHash: "hash-\(name)"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: seatMinC, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false),
            ResultMetric(name: "seat_pass_ratio", value: 1, unit: "1", method: "l2_seat_gate", fidelity: .l2, omitted: false),
            ResultMetric(name: "q_cool_w", value: watts * 3, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
            ResultMetric(name: "p_elec_w", value: watts, unit: "W", method: "equivalent_ideal_loads", fidelity: .l1, omitted: false),
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
