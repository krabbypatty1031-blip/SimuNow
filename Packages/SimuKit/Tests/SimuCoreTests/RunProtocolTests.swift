import Foundation
import Testing
@testable import SimuCore
@testable import SimuSimulation

private let runID = UUID(uuidString: "3392F7E1-1234-4000-8000-0000000000AB")!

private func line(_ type: String, _ sequence: Int, extra: String = "", id: UUID = runID) -> String {
    "{\"protocol\":\"run-event/1\",\"runID\":\"\(id.uuidString)\",\"sequence\":\(sequence),\"timestamp\":\"2026-10-03T01:23:45.678Z\",\"eventType\":\"\(type)\"\(extra)}"
}

@Test func parserAcceptsChunkedValidStream() throws {
    var parser = RunEventStreamParser(expectedRunID: runID)
    let text = [line("accepted", 1, extra: ",\"payload\":{\"fidelity\":\"l0\",\"note\":\"未知可选字段容忍\"}"),
                line("progress", 2, extra: ",\"stage\":\"solving\",\"payload\":{\"step\":4,\"totalSteps\":48}"),
                line("completed", 3)].joined(separator: "\n") + "\n"
    let bytes = Data(text.utf8)
    // Split in the middle of a line: partial pushes must not emit or lose events.
    let cut = bytes.index(bytes.startIndex, offsetBy: bytes.count / 2)
    let first = try parser.push(bytes.prefix(upTo: cut))
    #expect(first.count == 1)
    #expect(first[0].eventType == .accepted)
    let second = try parser.push(bytes.suffix(from: cut))
    #expect(second.map(\.eventType) == [.progress, .completed])
    #expect(second[1].eventType.isTerminal)
    #expect(try parser.finish().isEmpty)
}

@Test func parserRejectsWrongRunOutOfOrderGapAndUnknownType() throws {
    // Wrong run
    var parser = RunEventStreamParser(expectedRunID: runID)
    #expect(throws: RunProtocolError.wrongRun(expected: runID, actual: UUID(uuidString: "3392F7E1-1234-4000-8000-0000000000CD")!)) {
        try parser.push(Data((line("accepted", 1, id: UUID(uuidString: "3392F7E1-1234-4000-8000-0000000000CD")!) + "\n").utf8))
    }
    // Out of order (replayed sequence)
    parser = RunEventStreamParser(expectedRunID: runID)
    _ = try parser.push(Data((line("accepted", 1) + "\n").utf8))
    #expect(throws: RunProtocolError.sequenceViolation(expected: 2, actual: 1)) {
        try parser.push(Data((line("progress", 1) + "\n").utf8))
    }
    // Gap (truncated middle)
    parser = RunEventStreamParser(expectedRunID: runID)
    _ = try parser.push(Data((line("accepted", 1) + "\n").utf8))
    #expect(throws: RunProtocolError.sequenceViolation(expected: 2, actual: 5)) {
        try parser.push(Data((line("completed", 5) + "\n").utf8))
    }
    // Unknown event type
    parser = RunEventStreamParser(expectedRunID: runID)
    #expect(throws: RunProtocolError.unknownEventType("halfDone")) {
        try parser.push(Data((line("halfDone", 1) + "\n").utf8))
    }
    // Truncated final partial line is not valid JSON
    parser = RunEventStreamParser(expectedRunID: runID)
    _ = try parser.push(Data("{\"protocol\":\"run-event/1\",\"runID".utf8))
    #expect(throws: RunProtocolError.invalidJSON("line is not valid JSON")) {
        try parser.finish()
    }
    // Blank lines are tolerated
    parser = RunEventStreamParser(expectedRunID: runID)
    let events = try parser.push(Data(("\n" + line("accepted", 1) + "\n\n").utf8))
    #expect(events.count == 1)
}

@Test func resultDecodesMissingBoolAndError() throws {
    let hash = String(repeating: "a", count: 64)
    let text = """
    {"protocol":"run-result/1","identity":{"runID":"\(runID.uuidString)","scenarioID":"00000000-0000-4000-8000-000000000003","inputHash":"\(hash)"},"fidelity":"l0","state":"completed",
    "metrics":[
      {"name":"coolingLoadPeak","value":3120.5,"unit":"W","aggregation":"representative_day","method":"l0_steady_state","fidelity":"l0"},
      {"name":"capacityAdequate","value":true,"unit":"1","aggregation":"representative_day","method":"l0_steady_state","fidelity":"l0"},
      {"name":"dailyCost","value":null,"unit":"currency","missing_reason":"缺少币种或电价；不编造费用","aggregation":"representative_day","method":"l0_steady_state","fidelity":"l0"}],
    "quality":{"state":"passed","checks":[{"name":"energy_balance","state":"passed","max_residual_W":0}]},
    "assumptions":["L0 集总平均模型"],"startedAt":"2026-10-03T01:23:45.678Z","finishedAt":"2026-10-03T01:23:46.678Z"}
    """
    let result = try RunResult.load(from: Data(text.utf8))
    #expect(result.identity.runID == runID)
    #expect(result.state == .completed)
    #expect(result.metric(named: "coolingLoadPeak")?.doubleValue == 3120.5)
    #expect(result.metric(named: "capacityAdequate")?.boolValue == true)
    let cost = try #require(result.metric(named: "dailyCost"))
    #expect(cost.isMissing)
    #expect(cost.missingReason?.contains("不编造费用") == true)
    #expect(cost.doubleValue == nil) // missing is never zero
    #expect(result.quality.state == .passed)
    #expect(result.assumptions.count == 1)
    #expect(result.error == nil)

    let failedText = """
    {"protocol":"run-result/1","identity":{"runID":"\(runID.uuidString)","scenarioID":"00000000-0000-4000-8000-000000000003","inputHash":"\(hash)"},"fidelity":"l0","state":"failed","metrics":[],"quality":{"state":"notEvaluated","checks":[]},"assumptions":[],"startedAt":"2026-10-03T01:23:45.678Z","finishedAt":"2026-10-03T01:23:46.000Z","error":{"kind":"adapter_error","message":"boom"}}
    """
    let failed = try RunResult.load(from: Data(failedText.utf8))
    #expect(failed.state == .failed)
    #expect(failed.error?.kind == "adapter_error")

    // Wrong protocol marker is rejected.
    #expect(throws: RunProtocolError.self) {
        try RunResult.load(from: Data(text.replacingOccurrences(of: "run-result/1", with: "run-result/2").utf8))
    }
}

@Test func runInputEncodesIdentityConsistentWithSnapshot() throws {
    let project = ProjectTemplates.office()
    let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: project.scenarios[0].id)
    let input = try RunInput(fidelity: .l0, snapshot: snapshot)
    #expect(input.identity.scenarioID == snapshot.scenarioID)
    #expect(try InputHash.snapshotHash(snapshot) == input.identity.inputHash)
    let node = try JSONValue(data: input.encoded())
    #expect(node["protocol"] == .string("run-input/1"))
    #expect(node["fidelity"] == .string("l0"))
    #expect(node["runID"]?.string == input.identity.runID.uuidString.uppercased())
    #expect(node["snapshot"]?["scenarioID"]?.string == snapshot.scenarioID.uuidString.uppercased())
}

@Test func swiftWritesRunInputForPythonVerification() throws {
    guard let path = ProcessInfo.processInfo.environment["SIMUNOW_CONTRACT_DIR"] else { return }
    let directory = URL(fileURLWithPath: path)
    let codec = ProjectCodec(registry: .builtIn)
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    for name in ["office", "classroom"] {
        let project = try codec.decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/\(name).json")))
        let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: project.scenarios[0].id)
        let input = try RunInput(fidelity: .l0, snapshot: snapshot)
        try input.encoded().write(to: directory.appendingPathComponent("\(name).swift-runinput.json"))
    }
}
