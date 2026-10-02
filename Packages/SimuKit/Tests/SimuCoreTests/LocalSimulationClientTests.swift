import Foundation
import Testing
@testable import SimuCore
@testable import SimuSimulation

@Test func unavailableRunClientThrowsHonestError() async {
    let client = UnavailableRunClient(reason: "iOS 不执行本地计算；远程节点后续接入。")
    let job = RunJob(identity: RunIdentity(scenarioID: UUID(), inputHash: "hash"),
                     fidelity: .l0, runDirectoryURL: URL(fileURLWithPath: "/tmp/unused"))
    do {
        for try await _ in client.events(for: job) {}
        Issue.record("An unavailable executor must not produce a successful stream.")
    } catch {
        #expect(error as? RunClientError == .unavailable("iOS 不执行本地计算；远程节点后续接入。"))
    }
    do {
        try await client.cancel(job)
        Issue.record("Cancel on an unavailable executor must not pretend success.")
    } catch {
        #expect(error is RunClientError)
    }
}

@Test func workerEnvironmentResolvesOnlyExplicitConfiguration() {
    #expect(WorkerEnvironment.resolve(defaults: UserDefaults(), environment: [:]) == nil)
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    let python = root.appendingPathComponent("Backend/.venv/bin/python").path
    let src = root.appendingPathComponent("Backend/src").path
    let resolved = WorkerEnvironment.resolve(defaults: UserDefaults(),
                                             environment: ["SIMUNOW_WORKER_PYTHON": python, "SIMUNOW_WORKER_SRC": src])
    #expect(resolved?.isUsable == true)
    #expect(WorkerEnvironment.resolve(defaults: UserDefaults(),
                                      environment: ["SIMUNOW_WORKER_PYTHON": "/bin/false", "SIMUNOW_WORKER_SRC": src]) == nil)
}

#if os(macOS)
private func repositoryRoot() -> URL {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root
}

private func makeJob(in directory: URL) throws -> RunJob {
    let root = repositoryRoot()
    let project = try ProjectCodec(registry: .builtIn)
        .decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: project.scenarios[0].id)
    let input = try RunInput(fidelity: .l0, snapshot: snapshot)
    let runDirectory = directory.appendingPathComponent(input.identity.runID.uuidString)
    try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
    try input.encoded().write(to: runDirectory.appendingPathComponent("input.json"))
    return RunJob(identity: input.identity, fidelity: .l0, runDirectoryURL: runDirectory)
}

private func makeClient() throws -> LocalSimulationClient {
    let root = repositoryRoot()
    let environment = WorkerEnvironment(
        pythonExecutableURL: root.appendingPathComponent("Backend/.venv/bin/python"),
        workerSourceURL: root.appendingPathComponent("Backend/src"))
    try #require(environment.isUsable, "Backend/.venv 缺失；按 Backend/README.md 建立锁定 Python 环境")
    return LocalSimulationClient(environment: environment)
}

@Test func localClientRunsRealWorkerEndToEnd() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-localclient-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let job = try makeJob(in: directory)
    let client = try makeClient()
    var events: [RunEvent] = []
    for try await event in client.events(for: job) { events.append(event) }
    #expect(events.first?.eventType == .accepted)
    #expect(events.last?.eventType == .completed)
    #expect(events.map(\.sequence) == Array(1...events.count))
    #expect(events.contains { $0.eventType == .progress })
    #expect(events.contains { $0.eventType == .quality })
    let result = try RunResult.load(from: Data(contentsOf: job.runDirectoryURL.appendingPathComponent("result.json")))
    #expect(result.state == .completed)
    #expect(result.identity == job.identity)
    #expect(result.quality.state == .passed)
    #expect(result.metric(named: "dailyCoolingEnergy")?.doubleValue ?? 0 > 0)
    // A completed run never reports cancelled state; events.jsonl is on disk for audit.
    #expect(FileManager.default.fileExists(atPath: job.runDirectoryURL.appendingPathComponent("events.jsonl").path))
}

@Test func localClientCancelBeforeStartYieldsCancelled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-localclient-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let job = try makeJob(in: directory)
    let client = try makeClient()
    try await client.cancel(job)  // marker file before the process starts
    var events: [RunEvent] = []
    for try await event in client.events(for: job) { events.append(event) }
    #expect(events.map(\.eventType) == [.accepted, .cancelled])
    let result = try RunResult.load(from: Data(contentsOf: job.runDirectoryURL.appendingPathComponent("result.json")))
    #expect(result.state == .cancelled)
    // Repeated cancel is harmless.
    try await client.cancel(job)
}

@Test func localClientSurfacesCrashInsteadOfSilentSuccess() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-localclient-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = try makeClient()

    // Invalid envelope (wrong protocol): the worker exits 3 without any events.
    let crashJob = try makeJob(in: directory)
    var fields = try #require(try JSONValue(data: Data(contentsOf: crashJob.inputFileURL)).fields)
    fields["protocol"] = .string("run-input/0")
    try JSONValue.object(fields).data().write(to: crashJob.inputFileURL)
    do {
        for try await _ in client.events(for: crashJob) {}
        Issue.record("A worker exiting 3 without events must surface as a crash, not success.")
    } catch {
        #expect(error as? RunClientError == .workerCrashed(exitCode: 3))
    }

    // Corrupted hash: the worker emits a failed terminal event (exit 3) — a normal
    // stream ending whose result.json carries the evidence.
    let mismatchJob = try makeJob(in: directory)
    var mismatchFields = try #require(try JSONValue(data: Data(contentsOf: mismatchJob.inputFileURL)).fields)
    mismatchFields["inputHash"] = .string(String(repeating: "0", count: 64))
    try JSONValue.object(mismatchFields).data().write(to: mismatchJob.inputFileURL)
    var events: [RunEvent] = []
    for try await event in client.events(for: mismatchJob) { events.append(event) }
    #expect(events.last?.eventType == .failed)
    let result = try RunResult.load(from: Data(contentsOf: mismatchJob.runDirectoryURL.appendingPathComponent("result.json")))
    #expect(result.state == .failed)
    #expect(result.error?.kind == "input_hash_mismatch")
}
#endif
