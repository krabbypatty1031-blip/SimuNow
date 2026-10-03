#if os(macOS)
import Foundation
import Testing
import SimuCore
import SimuSimulation

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeRequest(runID: UUID, snapshot: Data, path: String = "runs/input.json") -> SimulationRequest {
    let digest = InputSnapshotHash.sha256Hex(snapshot)
    return SimulationRequest(
        identity: RunIdentity(runID: runID, scenarioID: UUID(), inputHash: digest),
        fidelity: .l1,
        snapshotPath: path,
        snapshotHash: digest
    )
}

@Test func stubWorkerEmitsJSONLAndRedactsHomeInLog() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-02-\(UUID().uuidString)", isDirectory: true)
    let snapshot = Data(#"{"schemaVersion":2,"name":"办公室"}"#.utf8)
    let request = makeRequest(runID: UUID(), snapshot: snapshot)
    let client = LocalProcessClient(repositoryRoot: repoRoot(), runRoot: root)
    let receipt = try await client.submit(request, snapshot: snapshot, extraArguments: [], workerCommand: "stub-task")
    let eventsURL = root.appendingPathComponent("\(request.identity.runID.uuidString)/events.jsonl")
    let logURL = root.appendingPathComponent("\(request.identity.runID.uuidString)/logs/stderr.log")
    let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? "<missing-log>"
    let events = (try? String(contentsOf: eventsURL, encoding: .utf8)) ?? "<missing-events>"
    #expect(receipt.state == .succeeded, "state=\(receipt.state) log=\(log) events=\(events)")
    #expect(receipt.quality == .notEvaluated)
    #expect(FileManager.default.fileExists(atPath: eventsURL.path))
    #expect(!log.lowercased().contains("/users/"))
    #expect(events.contains("completed"))
}

@Test func cancelIsIdempotentAndKeepsEvidence() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-02c-\(UUID().uuidString)", isDirectory: true)
    let snapshot = Data(#"{"schemaVersion":2}"#.utf8)
    let runID = UUID()
    let request = makeRequest(runID: runID, snapshot: snapshot)
    let client = LocalProcessClient(repositoryRoot: repoRoot(), runRoot: root)
    async let submitted = client.submit(request, snapshot: snapshot, extraArguments: ["--sleep", "8"], workerCommand: "stub-task")
    try await Task.sleep(for: .milliseconds(300))
    try await client.cancel(runID: runID)
    let receipt = try await submitted
    #expect(receipt.state == .cancelled)
    try await client.cancel(runID: runID)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(runID.uuidString)/request.json").path))
}

@Test func failedStubKeepsRunDirectoryAndDoesNotSucceed() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-02d-\(UUID().uuidString)", isDirectory: true)
    let snapshot = Data(#"{"schemaVersion":2}"#.utf8)
    let request = makeRequest(runID: UUID(), snapshot: snapshot)
    let client = LocalProcessClient(repositoryRoot: repoRoot(), runRoot: root)
    let receipt = try await client.submit(request, snapshot: snapshot, extraArguments: ["--fail"], workerCommand: "stub-task")
    let events = try String(
        contentsOf: root.appendingPathComponent("\(request.identity.runID.uuidString)/events.jsonl"),
        encoding: .utf8
    )
    #expect(receipt.state == .failed)
    #expect(receipt.quality != .passed)
    #expect(events.contains("\"eventType\":\"failed\""))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(request.identity.runID.uuidString)/logs/stderr.log").path))
}

@Test func identicalInputHashReusesSucceededRunID() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-05a-\(UUID().uuidString)", isDirectory: true)
    let snapshot = Data(#"{"schemaVersion":2,"cache":true}"#.utf8)
    let first = makeRequest(runID: UUID(), snapshot: snapshot)
    let second = makeRequest(runID: UUID(), snapshot: snapshot)
    let client = LocalProcessClient(repositoryRoot: repoRoot(), runRoot: root)
    let a = try await client.submit(first, snapshot: snapshot, extraArguments: [], workerCommand: "stub-task")
    let b = try await client.submit(second, snapshot: snapshot, extraArguments: [], workerCommand: "stub-task")
    #expect(a.state == .succeeded)
    #expect(b.identity.runID == a.identity.runID)
    #expect(b.identity.runID != second.identity.runID)
    #expect(b.identity.freshness(relativeTo: first.identity.inputHash) == .current)
    #expect(b.identity.freshness(relativeTo: "edited-room") == .stale)
}

@Test func timeoutFailsAndKeepsLogWithoutTouchingAnotherProject() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-05b-\(UUID().uuidString)", isDirectory: true)
    let snapshot = Data(#"{"schemaVersion":2,"timeout":true}"#.utf8)
    let request = makeRequest(runID: UUID(), snapshot: snapshot)
    let client = LocalProcessClient(repositoryRoot: repoRoot(), runRoot: root)
    let receipt = try await client.submit(request, snapshot: snapshot, extraArguments: ["--sleep", "8"], timeoutSeconds: 0.2, workerCommand: "stub-task")
    #expect(receipt.state == .failed)
    let log = try String(
        contentsOf: root.appendingPathComponent("\(request.identity.runID.uuidString)/logs/stderr.log"),
        encoding: .utf8
    )
    #expect(log.contains("timeout") || FileManager.default.fileExists(atPath: root.appendingPathComponent("\(request.identity.runID.uuidString)/request.json").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(request.identity.runID.uuidString)/request.json").path))
}

@Test func runL1WithoutEnginesFailsAndDoesNotWriteCoolingWatts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-06b-\(UUID().uuidString)", isDirectory: true)
    let draft = try ProjectTemplates.bundled(named: "office").project
    let snapshot = try JSONEncoder().encode(draft)
    let request = makeRequest(runID: UUID(), snapshot: snapshot)
    let client = LocalProcessClient(
        repositoryRoot: repoRoot(),
        runRoot: root,
        extraEnvironment: ["SIMUNOW_ENGINES_ROOT": ""]
    )
    let receipt = try await client.submit(request, snapshot: snapshot, workerCommand: "run-l1")
    #expect(receipt.state == .failed)
    let resultURL = root.appendingPathComponent("\(request.identity.runID.uuidString)/result.json")
    let result = try JSONDecoder().decode(SimulationResult.self, from: Data(contentsOf: resultURL))
    #expect(result.metric(named: "q_cool_w")?.omitted == true)
    #expect(result.metric(named: "q_cool_w")?.value != 0)
    #expect(result.metric(named: "p_elec_w")?.omitted == true)
    #expect(result.metric(named: "annual_kwh")?.omitted == true)
}

@Test func runL1WithPinnedEnginesWritesCoolingAndElectricity() async throws {
    let engines = repoRoot().appendingPathComponent("test/engines/EnergyPlus/energyplus")
    try #require(FileManager.default.isExecutableFile(atPath: engines.path))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-06c-\(UUID().uuidString)", isDirectory: true)
    let draft = try ProjectTemplates.bundled(named: "office").project
    let snapshot = try JSONEncoder().encode(draft)
    let request = makeRequest(runID: UUID(), snapshot: snapshot)
    let client = LocalProcessClient(
        repositoryRoot: repoRoot(),
        runRoot: root,
        extraEnvironment: ["SIMUNOW_ENGINES_ROOT": repoRoot().appendingPathComponent("test/engines").path]
    )
    let receipt = try await client.submit(request, snapshot: snapshot, timeoutSeconds: 180, workerCommand: "run-l1")
    let resultURL = root.appendingPathComponent("\(request.identity.runID.uuidString)/result.json")
    let raw = (try? String(contentsOf: resultURL, encoding: .utf8)) ?? "<missing-result>"
    #expect(receipt.state == RunState.succeeded, "state=\(receipt.state.rawValue) result=\(raw)")
    let result = try JSONDecoder().decode(SimulationResult.self, from: Data(contentsOf: resultURL))
    let cool = try #require(result.metric(named: "q_cool_w"))
    let elec = try #require(result.metric(named: "p_elec_w"))
    #expect(cool.omitted == false)
    #expect((cool.value ?? 0) > 0)
    #expect(cool.unit == "W")
    #expect(elec.unit == "W")
    #expect(abs((elec.value ?? 0) - (cool.value ?? 0) / 3.0) < 1e-3)
    #expect(result.metric(named: "annual_kwh")?.omitted == true)
    #expect(result.supplyTemperatureC == 16)
    #expect(result.setpointC == 26)
}
#endif
