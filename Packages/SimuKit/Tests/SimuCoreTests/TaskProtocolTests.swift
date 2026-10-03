import Foundation
import Testing
import SimuCore
import SimuSimulation

private let runA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
private let runB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
private let scenario = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

@Test func requestHashMustMatchSnapshotBytes() throws {
    let snapshot = Data(#"{"schemaVersion":2,"name":"办公室"}"#.utf8)
    let digest = InputSnapshotHash.sha256Hex(snapshot)
    let request = SimulationRequest(
        identity: RunIdentity(runID: runA, scenarioID: scenario, inputHash: digest),
        fidelity: .l1,
        snapshotPath: "runs/\(runA.uuidString)/input.json",
        snapshotHash: digest
    )
    try request.validate(snapshot: snapshot)
    var tampered = snapshot
    tampered[tampered.startIndex] = 0x20
    #expect(throws: TaskProtocolError.hashMismatch) {
        try request.validate(snapshot: tampered)
    }
}

@Test func requestRejectsAbsoluteWeatherPath() {
    let digest = InputSnapshotHash.sha256Hex(Data("x".utf8))
    let identity = RunIdentity(runID: runA, scenarioID: scenario, inputHash: digest)
    #expect(throws: TaskProtocolError.unsafeSnapshotPath) {
        try SimulationRequest(
            identity: identity,
            fidelity: .l1,
            snapshotPath: "runs/input.json",
            snapshotHash: digest,
            weatherPath: "/Users/krabbypatty/weather.epw",
            weatherHash: "h"
        ).validate(snapshot: Data("x".utf8))
    }
}

@Test func requestRejectsAbsoluteOrParentSnapshotPaths() {
    let digest = InputSnapshotHash.sha256Hex(Data("x".utf8))
    let identity = RunIdentity(runID: runA, scenarioID: scenario, inputHash: digest)
    #expect(throws: TaskProtocolError.unsafeSnapshotPath) {
        try SimulationRequest(
            identity: identity,
            fidelity: .l1,
            snapshotPath: "/Users/krabbypatty/office.json",
            snapshotHash: digest
        ).validate(snapshot: Data("x".utf8))
    }
    #expect(throws: TaskProtocolError.unsafeSnapshotPath) {
        try SimulationRequest(
            identity: identity,
            fidelity: .l1,
            snapshotPath: "../outside.json",
            snapshotHash: digest
        ).validate(snapshot: Data("x".utf8))
    }
}

@Test func eventStreamAcceptsStrictlyIncreasingSequences() throws {
    var stream = TaskEventStream(expectedRunID: runA)
    let accepted = try stream.ingest(jsonl([eventJSON(run: runA, sequence: 0), eventJSON(run: runA, sequence: 1)]))
    #expect(accepted.map(\.sequence) == [0, 1])
    #expect(stream.events.count == 2)
}

@Test func outOfOrderSequenceIsRejectedWithoutReordering() throws {
    var stream = TaskEventStream(expectedRunID: runA)
    _ = try stream.ingest(eventJSON(run: runA, sequence: 0) + "\n")
    #expect(throws: TaskProtocolError.staleSequence) {
        try stream.ingest(eventJSON(run: runA, sequence: 0) + "\n")
    }
    #expect(stream.events.map(\.sequence) == [0])
}

@Test func truncatedLineStaysBufferedUntilNewline() throws {
    var stream = TaskEventStream(expectedRunID: runA)
    let line = eventJSON(run: runA, sequence: 0)
    let added = try stream.ingest(String(line.prefix(20)))
    #expect(added.isEmpty)
    #expect(stream.events.isEmpty)
    let completed = try stream.ingest(String(line.dropFirst(20)) + "\n")
    #expect(completed.count == 1)
    #expect(throws: TaskProtocolError.truncatedLine) {
        var hanging = TaskEventStream(expectedRunID: runA)
        _ = try hanging.ingest(#"{"schemaVersion":1"#)
        try hanging.finish()
    }
}

@Test func eventForAnotherRunIsRejected() throws {
    var stream = TaskEventStream(expectedRunID: runA)
    #expect(throws: TaskProtocolError.wrongRun) {
        try stream.ingest(eventJSON(run: runB, sequence: 0) + "\n")
    }
    #expect(stream.events.isEmpty)
}

@Test func resultOmitsMissingEnergyInsteadOfZero() throws {
    let json = """
    {
      "schemaVersion": 1,
      "identity": {
        "runID": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "scenarioID": "cccccccc-cccc-cccc-cccc-cccccccccccc",
        "inputHash": "abc"
      },
      "state": "succeeded",
      "quality": "notEvaluated",
      "period": {"kind":"representative_day","start":"07-15","end":"07-15"},
      "metrics": [
        {"name":"q_cool_w","value":6334.87,"unit":"W","method":"equivalent_ideal_loads","fidelity":"l1","omitted":false},
        {"name":"p_elec_w","value":2111.62,"unit":"W","method":"equivalent_ideal_loads","fidelity":"l1","omitted":false},
        {"name":"annual_kwh","value":null,"unit":"kWh","method":"not_modeled","fidelity":"l1","omitted":true}
      ]
    }
    """
    let result = try JSONDecoder().decode(SimulationResult.self, from: Data(json.utf8))
    #expect(result.metric(named: "q_cool_w")?.value == 6334.87)
    #expect(result.metric(named: "p_elec_w")?.value == 2111.62)
    #expect(result.metric(named: "annual_kwh")?.value == nil)
    #expect(result.metric(named: "annual_kwh")?.omitted == true)
    #expect(result.metric(named: "annual_kwh")?.value != 0)
    #expect(result.period?.kind == "representative_day")
    #expect(result.quality == .notEvaluated)
}

private func eventJSON(run: UUID, sequence: Int) -> String {
    """
    {"schemaVersion":1,"runID":"\(run.uuidString)","scenarioID":"\(scenario.uuidString)","inputHash":"abc","sequence":\(sequence),"timestamp":"2026-10-03T02:00:00Z","eventType":"progress","stage":"solving","payload":{"fraction":0.2,"monitor":"continuity"}}
    """
}

private func jsonl(_ lines: [String]) -> String {
    lines.joined(separator: "\n") + "\n"
}
