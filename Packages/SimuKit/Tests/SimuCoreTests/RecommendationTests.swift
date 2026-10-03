import Foundation
import Testing
import SimuCore

/// Two same-basis L2 runs whose supply heights differ, and whose seat
/// temperatures differ, are a comfort comparison. The card must cite both
/// L2 run IDs and record that quality passed.
@Test func sameBasisSupplyHeightChangeYieldsComfortCardCitingBothL2Runs() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let low = try candidate(
        name: "低送风口",
        draft: supplyHeight(office, z0: 2.10, z1: 2.28),
        seatMinC: 24.21,
        passRatio: 1,
        passCount: 8,
        evalCount: 8
    )
    let high = try candidate(
        name: "默认送风口",
        draft: office,
        seatMinC: 24.43,
        passRatio: 1,
        passCount: 8,
        evalCount: 8
    )

    let cards = RecommendationClassifier.cards(from: [low, high])
    let comfort = try #require(cards.first { $0.kind == .comfort })
    #expect(comfort.qualityPassed)
    #expect(comfort.citedRunIDs.contains(low.identity.runID))
    #expect(comfort.citedRunIDs.contains(high.identity.runID))
    let blob = cards.map(\.prose).joined(separator: "\n")
    #expect(!blob.contains("全局最优"))
    #expect(!blob.contains("满意率"))
}

/// A field that never passed quality is an explanation, not a named scheme.
@Test func noQualityPassedFieldIsExplanationOnly() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let failed = try candidate(
        name: "未通过",
        draft: office,
        quality: .failed,
        seatMinC: nil,
        passRatio: nil,
        passCount: nil,
        evalCount: nil,
        ratioOmitted: true
    )
    let cards = RecommendationClassifier.cards(from: [failed])
    #expect(cards.count == 1)
    #expect(cards[0].kind == .explanation)
    #expect(!cards[0].qualityPassed)
    #expect(cards[0].citedRunIDs == [failed.identity.runID])
    let blob = cards.map(\.prose).joined(separator: "\n")
    #expect(!blob.contains("推荐方案"))
    #expect(cards.allSatisfy { $0.kind != .comfort && $0.kind != .operation && $0.kind != .retrofit })
}

/// Every evaluated seat failing is the same gate: explain, do not rank a scheme.
@Test func allSeatsFailingIsExplanationOnly() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let blocked = try candidate(
        name: "全部门失败",
        draft: office,
        seatMinC: 27,
        passRatio: 0,
        passCount: 0,
        evalCount: 4
    )
    let cards = RecommendationClassifier.cards(from: [blocked])
    #expect(cards.allSatisfy { $0.kind == .explanation })
    #expect(!cards.map(\.prose).joined().contains("推荐方案"))
}

/// Equipment changes stay unquoted. The card lists assumptions and omits payback.
@Test func retrofitWithoutQuoteSaysPendingAndOmitsPayback() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let low = try candidate(
        name: "低送风口",
        draft: supplyHeight(office, z0: 2.10, z1: 2.28),
        seatMinC: 24.21,
        passRatio: 1,
        passCount: 8,
        evalCount: 8,
        watts: 1000
    )
    let high = try candidate(
        name: "默认送风口",
        draft: office,
        seatMinC: 24.43,
        passRatio: 0.75,
        passCount: 6,
        evalCount: 8,
        watts: 1500
    )

    let cards = RecommendationClassifier.cards(from: [low, high])
    let retrofit = try #require(cards.first { $0.kind == .retrofit })
    #expect(retrofit.quoteStatus == "待报价")
    #expect(retrofit.detail.contains("待报价"))
    #expect(retrofit.payback == nil)
    #expect(!retrofit.assumptions.isEmpty)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(retrofit)) as? [String: Any]
    #expect(encoded?["payback"] == nil)
    #expect(cards.contains { $0.kind == .operation })
    #expect(cards.contains { $0.kind == .comfort })
    // Constraints, then comfort, then cost. A partial miss leads; payback never appears.
    let kinds = cards.map(\.kind)
    #expect(kinds.firstIndex(of: .comfort)! < kinds.firstIndex(of: .operation)!)
    #expect(kinds.firstIndex(of: .operation)! < kinds.firstIndex(of: .retrofit)!)
}

/// Same-basis L1 costs that differ are an operation card citing the L1 run IDs.
@Test func operationCardCitesL1RunIDsWhenDayCostsDiffer() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let cheaper = try candidate(
        name: "较低电功率",
        draft: supplyHeight(office, z0: 2.10, z1: 2.28),
        seatMinC: 24.21,
        passRatio: 1,
        passCount: 8,
        evalCount: 8,
        watts: 1000
    )
    let costlier = try candidate(
        name: "较高电功率",
        draft: office,
        seatMinC: 24.43,
        passRatio: 1,
        passCount: 8,
        evalCount: 8,
        watts: 1500
    )
    let saved = try #require(CostAccounting.savingsHKD(costlier.dayCost, cheaper.dayCost, basisMismatch: nil))
    let cards = RecommendationClassifier.cards(from: [cheaper, costlier])
    let operation = try #require(cards.first { $0.kind == .operation })
    #expect(operation.citedRunIDs.contains(cheaper.l1Identity!.runID))
    #expect(operation.citedRunIDs.contains(costlier.l1Identity!.runID))
    #expect(operation.detail.contains(String(format: "%.3f", saved)))
    #expect(!operation.detail.contains("无电费差"))
}

/// Equal L1 day costs must say so. A missing delta is not a hidden savings claim.
@Test func operationCardStatesNoElectricityDifferenceWhenCostsMatch() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let left = try candidate(
        name: "甲",
        draft: supplyHeight(office, z0: 2.10, z1: 2.28),
        seatMinC: 24.21,
        passRatio: 1,
        passCount: 8,
        evalCount: 8,
        watts: 1033.112
    )
    let right = try candidate(
        name: "乙",
        draft: office,
        seatMinC: 24.43,
        passRatio: 1,
        passCount: 8,
        evalCount: 8,
        watts: 1033.112
    )
    let operation = try #require(RecommendationClassifier.cards(from: [left, right]).first { $0.kind == .operation })
    #expect(operation.detail.contains("无电费差"))
    #expect(operation.citedRunIDs.contains(left.l1Identity!.runID))
    #expect(operation.citedRunIDs.contains(right.l1Identity!.runID))
}

private func supplyHeight(_ draft: ProjectDraft, z0: Double, z1: Double) throws -> ProjectDraft {
    var copy = draft
    let supply = try #require(copy.hvac?.supply)
    _ = copy.applySupplyTerminal(
        wall: supply.wall,
        s0: supply.s0.value,
        s1: supply.s1.value,
        z0: z0,
        z1: z1,
        source: .user
    )
    return copy
}

private func candidate(
    name: String,
    draft: ProjectDraft,
    quality: QualityState = .passed,
    seatMinC: Double?,
    passRatio: Double?,
    passCount: Double?,
    evalCount: Double?,
    ratioOmitted: Bool = false,
    watts: Double? = nil
) throws -> CandidateRun {
    var metrics: [ResultMetric] = []
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

private extension RecommendationCard {
    var prose: String { title + "\n" + detail + "\n" + assumptions.joined(separator: "\n") }
}
