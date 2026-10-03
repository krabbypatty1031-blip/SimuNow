import Foundation
import Testing
import SimuCore

private func fixturesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/task")
}

@Test func qualityDetailRequiresEveryGateToPass() {
    let allPass = QualityDetail(
        checkMesh: "ok",
        solverEnded: true,
        monitorsStable: true,
        massRelativeError: 0.0004,
        massGate: 0.01,
        energyRelativeError: 0.003,
        energyGate: 0.05
    )
    #expect(allPass.allGatesPass)

    // One unstable monitor is a failed field even when conservation looks fine.
    #expect(!QualityDetail(checkMesh: "ok", solverEnded: true, monitorsStable: false, massRelativeError: 0.001, massGate: 0.01, energyRelativeError: 0.004, energyGate: 0.05).allGatesPass)
    #expect(!QualityDetail(checkMesh: "failed", solverEnded: true, monitorsStable: true, massRelativeError: 0.001, massGate: 0.01, energyRelativeError: 0.004, energyGate: 0.05).allGatesPass)

    // Missing logs never pass; a missing gate is not a zero error.
    #expect(!QualityDetail().allGatesPass)
    #expect(!QualityDetail(checkMesh: "ok", solverEnded: true, monitorsStable: true).allGatesPass)
    #expect(!QualityDetail(checkMesh: "ok", solverEnded: true, monitorsStable: true, massRelativeError: 0.001, massGate: 0.01, energyRelativeError: 0.004).allGatesPass)
}

@Test func qualityDetailFailsWhenRelativeErrorExceedsGate() {
    #expect(!QualityDetail(
        checkMesh: "ok",
        solverEnded: true,
        monitorsStable: true,
        massRelativeError: 0.02,
        massGate: 0.01,
        energyRelativeError: 0.003,
        energyGate: 0.05
    ).allGatesPass)
}

@Test func l2ResultDecodesSeatSamplesAndKeepsQualitySeparate() throws {
    let data = try Data(contentsOf: fixturesDirectory().appendingPathComponent("result-l2.json"))
    let result = try JSONDecoder().decode(SimulationResult.self, from: data)
    #expect(result.state == .succeeded)
    #expect(result.quality == .passed)
    let detail = try #require(result.qualityDetail)
    #expect(detail.allGatesPass)
    #expect(detail.checkMesh == "ok")

    let seats = try #require(result.seatSamples)
    #expect(seats.count == 4)
    #expect(seats.map(\.id) == ["S1", "S2", "S3", "S4"])
    #expect(seats.allSatisfy { $0.tC > 15 })
    #expect(seats.contains { $0.lowSpeedAbsoluteError == true })

    // Aggregate metrics match the per-seat samples; they are not position claims.
    let minMetric = try #require(result.metric(named: "seat_t_c_min"))
    #expect(!minMetric.omitted)
    #expect(minMetric.value == seats.map(\.tC).min())
    let maxMetric = try #require(result.metric(named: "seat_t_c_max"))
    #expect(maxMetric.value == seats.map(\.tC).max())
    let uMaxMetric = try #require(result.metric(named: "seat_u_mag_max"))
    #expect(uMaxMetric.unit == "m/s")
    #expect(uMaxMetric.value == seats.map(\.uMag).max())
    #expect(minMetric.fidelity == .l2)
}

@Test func l2ResultCarriesOmittedComfortMetricsWithReason() throws {
    // The pinned run has no comfort inputs, so PMV stays omitted with a
    // reason; it is never filled with a neutral 0 vote.
    let data = try Data(contentsOf: fixturesDirectory().appendingPathComponent("result-l2.json"))
    let result = try JSONDecoder().decode(SimulationResult.self, from: data)

    let pmvMin = try #require(result.metric(named: "seat_pmv_min"))
    #expect(pmvMin.omitted)
    #expect(pmvMin.value == nil)
    #expect(pmvMin.unit == "index")
    #expect(pmvMin.method == "not_modeled")
    #expect(pmvMin.fidelity == .l2)
    let reason = try #require(pmvMin.reason)
    #expect(reason.contains("missing"))
    #expect(reason.contains("mrtC"))
    #expect(reason.contains("rhPct"))

    let ppdMax = try #require(result.metric(named: "seat_ppd_max"))
    #expect(ppdMax.omitted)
    #expect(ppdMax.value == nil)
    #expect(ppdMax.unit == "%")

    // Seats carry no PMV of their own while inputs are missing.
    let seats = try #require(result.seatSamples)
    #expect(seats.allSatisfy { $0.pmv == nil && $0.ppd == nil })
}

@Test func l1ResultStillDecodesWithoutL2Fields() throws {
    // The L1 fixture predates qualityDetail/seatSamples; decoding must stay backward compatible.
    let data = try Data(contentsOf: fixturesDirectory().appendingPathComponent("result-l1.json"))
    let result = try JSONDecoder().decode(SimulationResult.self, from: data)
    #expect(result.qualityDetail == nil)
    #expect(result.seatSamples == nil)
    #expect(result.metric(named: "q_cool_w")?.value == 6334.87)
}
