import Foundation
import Testing
import SimuCore

/// Geometry edits (supply height) stay on the comparison axis. Occupant
/// count, hours, setpoint and supply temperature change the basis.
@Test func decisionVariablesSeparateGeometryFromBasis() {
    #expect(DecisionVariables.geometryPaths.contains("hvac.supply.z0"))
    #expect(DecisionVariables.geometryPaths.contains("hvac.supply.z1"))
    #expect(DecisionVariables.basisPaths.contains("occupancy.occupantCount"))
    #expect(DecisionVariables.basisPaths.contains("hvac.setpointC"))
    #expect(DecisionVariables.basisPaths.contains("hvac.supplyTemperatureC"))
    #expect(!DecisionVariables.geometryPaths.contains("hvac.setpointC"))
    #expect(!DecisionVariables.basisPaths.contains("hvac.supply.z0"))
}

/// Review keeps every pinned candidate. A setpoint change is a warning, not
/// a silent drop that would make the remaining pair look like a valid set.
@Test func reviewKeepsMismatchedCandidatesAndWarns() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let matching = candidate(name: "基准", draft: office, setpoint: 26)
    var taller = office
    let supply = try #require(office.hvac?.supply)
    _ = taller.applySupplyTerminal(
        wall: supply.wall,
        s0: supply.s0.value,
        s1: supply.s1.value,
        z0: 2.10,
        z1: 2.28,
        source: .user
    )
    let geometry = candidate(name: "降低口", draft: taller, setpoint: 26)
    var warmer = office
    warmer.hvac?.setpointC.value = 24
    let basisShift = candidate(name: "改设定", draft: warmer, setpoint: 24)

    let review = DecisionVariables.review([matching, geometry, basisShift])
    #expect(review.candidates.count == 3)
    #expect(review.basisWarning?.contains("设定温度") == true)
    #expect(review.basisWarning?.contains("不能直接比") == true)
}

@Test func reviewOfMatchingCandidatesHasNoWarning() throws {
    let office = try ProjectTemplates.bundled(named: "office").project
    let a = candidate(name: "A", draft: office, setpoint: 26)
    let b = candidate(name: "B", draft: office, setpoint: 26)
    let review = DecisionVariables.review([a, b])
    #expect(review.basisWarning == nil)
    #expect(review.candidates.count == 2)
}

private func candidate(name: String, draft: ProjectDraft, setpoint: Double) -> CandidateRun {
    CandidateRun(
        name: name,
        identity: RunIdentity(scenarioID: draft.id, inputHash: name),
        state: .succeeded,
        quality: .passed,
        metrics: [],
        basis: CandidateRun.ComparisonBasis(
            occupantCount: draft.occupancy?.occupantCount.value ?? 8,
            occupiedStart: draft.occupancy?.schedule?.start ?? "08:00",
            occupiedEnd: draft.occupancy?.schedule?.end ?? "18:00",
            setpointC: setpoint,
            supplyTemperatureC: draft.hvac?.supplyTemperatureC.value ?? 16
        ),
        draft: draft
    )
}
