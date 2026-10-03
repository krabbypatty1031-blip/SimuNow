import Foundation
import Testing
import SimuCore

private func basis(
    occupants: Double = 8,
    start: String = "09:00",
    end: String = "18:00",
    setpoint: Double = 26,
    supply: Double = 16
) -> CandidateRun.ComparisonBasis {
    CandidateRun.ComparisonBasis(
        occupantCount: occupants,
        occupiedStart: start,
        occupiedEnd: end,
        setpointC: setpoint,
        supplyTemperatureC: supply
    )
}

/// Candidates with the same basis (weather, people, hours, setpoints) differ
/// only in geometry; that is the comparison the phase promises.
@Test func sameBasisIsComparable() {
    #expect(CandidateRun.basisMismatch(basis(), basis()) == nil)
}

/// Different occupant counts must not be shown side by side as a valid
/// comparison; the mismatch reason names the offending basis field.
@Test func differentOccupantCountBlocksComparison() {
    let reason = CandidateRun.basisMismatch(basis(), basis(occupants: 10))
    #expect(reason != nil)
    #expect(reason?.contains("人数") == true)
}

@Test func differentHoursAndSetpointsBlockComparison() {
    let hours = CandidateRun.basisMismatch(basis(), basis(start: "08:00", end: "17:00"))
    #expect(hours?.contains("占用时段") == true)
    let setpoint = CandidateRun.basisMismatch(basis(), basis(setpoint: 24))
    #expect(setpoint?.contains("设定温度") == true)
    let supply = CandidateRun.basisMismatch(basis(), basis(supply: 18))
    #expect(supply?.contains("送风温度") == true)
}

/// The pinned record is a frozen copy: metric values and slice survive as
/// evidence of the run, not as live views of the project.
@Test func candidateRunRoundTripsThroughCodable() throws {
    let record = CandidateRun(
        name: "方案 A",
        identity: RunIdentity(runID: UUID(), scenarioID: UUID(), inputHash: "hash-a"),
        state: .succeeded,
        quality: .passed,
        metrics: [
            ResultMetric(name: "seat_t_c_min", value: 25.08, unit: "C", method: "steady_cfd", fidelity: .l2, omitted: false)
        ],
        slice: FieldSlice(
            zM: 1.1,
            originM: FieldSlice.SliceOrigin(x: 0.1, y: 0.1),
            spacingM: FieldSlice.SliceOrigin(x: 0.25, y: 0.25),
            shape: FieldSlice.SliceShape(nx: 2, ny: 2),
            values: [[25.0, 25.1], [25.2, 25.3]],
            valid: [[true, true], [true, true]],
            stats: FieldSlice.SliceStats(validCount: 4, minC: 25.0, maxC: 25.3),
            inputHash: "hash-a"
        ),
        basis: basis(),
        draft: try ProjectTemplates.bundled(named: "office").project
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(CandidateRun.self, from: try encoder.encode(record))
    #expect(decoded == record)
    #expect(decoded.slice?.stats.maxC == 25.3)
}
