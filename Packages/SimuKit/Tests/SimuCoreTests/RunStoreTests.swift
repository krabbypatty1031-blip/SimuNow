import Foundation
import Testing
@testable import SimuCore
@testable import SimuSimulation
@testable import SimuWorkspace

/// Lock-protected call counter for the fake executor.
final class CancelCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Scripted executor: emits a valid event stream and writes result.json into the run
/// directory before the terminal event, like the real worker.
struct FakeRunClient: RunClient {
    let counter: CancelCounter
    var unavailableReason: String? { nil }

    private func event(_ type: String, _ sequence: Int, runID: UUID) throws -> (RunEvent, String) {
        let node: JSONValue = .object([
            "protocol": .string("run-event/1"),
            "runID": .string(runID.uuidString),
            "sequence": .number("\(sequence)"),
            "timestamp": .string("2026-10-03T01:00:00.000Z"),
            "eventType": .string(type),
        ])
        return (try RunEvent(node: node), try node.text())
    }

    func events(for job: RunJob) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let eventsURL = job.runDirectoryURL.appendingPathComponent("events.jsonl")
                var lines: [String] = []
                func emit(_ type: String, _ sequence: Int) throws {
                    let (event, line) = try event(type, sequence, runID: job.identity.runID)
                    lines.append(line)
                    continuation.yield(event)
                }
                try emit("accepted", 1)
                try emit("progress", 2)
                let result = RunResult(
                    identity: job.identity, fidelity: .l0, state: .completed,
                    metrics: [RunMetric(name: "dailyCoolingEnergy", value: .number("5.0"), unit: "kWh",
                                        aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0"),
                              RunMetric(name: "dailyCost", value: nil, unit: "currency", missingReason: "缺少币种或电价；不编造费用",
                                        aggregation: "representative_day", method: "l0_steady_state", fidelity: "l0")],
                    quality: RunQuality(state: .passed, checks: [.object(["name": .string("energy_balance"), "state": .string("passed")])]),
                    assumptions: ["L0 集总平均模型"],
                    startedAt: "2026-10-03T01:00:00.000Z", finishedAt: "2026-10-03T01:00:01.000Z")
                let data = try JSONTreeCoding.encode(result).data()
                try data.write(to: job.runDirectoryURL.appendingPathComponent("result.json"))
                try emit("completed", 3)
                try (lines.joined(separator: "\n") + "\n").write(to: eventsURL, atomically: false, encoding: .utf8)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func cancel(_ job: RunJob) async throws {
        counter.increment()
    }
}

@MainActor
struct RunStoreTests {
    private func fixtureProject() throws -> ProjectDocument {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try ProjectCodec(registry: .builtIn)
            .decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    }

    private func makeStore(in directory: URL) -> RunStore {
        RunStore(client: FakeRunClient(counter: CancelCounter()), baseDirectory: directory)
    }

    @Test func submitTracksResultAndFreshness() async throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-runstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        store.syncHashes(project: project)

        await store.submitL0(project: project, scenarioID: scenarioID, validator: ProjectValidator(), registry: .builtIn)
        let record = try #require(store.records.first)
        #expect(record.status == .completed)
        #expect(record.result?.quality.state == .passed)
        #expect(record.result?.metric(named: "dailyCoolingEnergy")?.doubleValue == 5.0)
        #expect(record.result?.metric(named: "dailyCost")?.isMissing == true)
        #expect(record.events.map(\.eventType) == [.accepted, .progress, .completed])
        #expect(record.freshness(relativeTo: store.currentHash(for: scenarioID)) == .current)
        #expect(FileManager.default.fileExists(atPath: record.runDirectory.appendingPathComponent("input.json").path))

        // Editing any physical input marks the old result stale; it is never deleted.
        var edited = project
        edited.scenarios[0].inputs.controls[0].setpoint = .known(value: 24, source: .init(kind: .user))
        store.syncHashes(project: edited)
        #expect(record.freshness(relativeTo: store.currentHash(for: scenarioID)) == .stale)

        // A second run lives in its own directory; the old record is untouched.
        await store.submitL0(project: edited, scenarioID: scenarioID, validator: ProjectValidator(), registry: .builtIn)
        #expect(store.records.count == 2)
        #expect(store.records[1].id == record.id)
        #expect(store.records[0].id != record.id)
        #expect(store.records[0].runDirectory != record.runDirectory)
    }

    @Test func reloadRestoresRunsAndMarksInterrupted() async throws {
        let project = try fixtureProject()
        let scenarioID = project.scenarios[0].id
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-runstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        await store.submitL0(project: project, scenarioID: scenarioID, validator: ProjectValidator(), registry: .builtIn)
        #expect(store.records.count == 1)

        // A directory with input.json but no result.json is an interrupted run.
        let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID)
        let ghost = try RunInput(fidelity: .l0, snapshot: snapshot)
        let ghostDir = directory.appendingPathComponent(project.id.uuidString)
            .appendingPathComponent(scenarioID.uuidString)
            .appendingPathComponent(ghost.identity.runID.uuidString)
        try FileManager.default.createDirectory(at: ghostDir, withIntermediateDirectories: true)
        try ghost.encoded().write(to: ghostDir.appendingPathComponent("input.json"))

        let reloaded = makeStore(in: directory)
        reloaded.loadFromDisk(projectID: project.id)
        #expect(reloaded.records.count == 2)
        #expect(reloaded.records.contains { $0.status == .completed })
        #expect(reloaded.records.contains { $0.status == .interrupted })
        // Integrity: a truncated events.jsonl is reported, not silently accepted.
        let completed = try #require(reloaded.records.first { $0.status == .completed })
        #expect(completed.events.isEmpty == false)
    }

    @Test func validationGateBlocksSubmit() async throws {
        // A cleared outdoor temperature still blocks preparation, so nothing is submitted.
        var project = ProjectTemplates.office()
        project.scenarios[0].inputs.environment.outdoorTemperature = .unknown(reason: "test")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-runstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        await store.submitL0(project: project, scenarioID: project.scenarios[0].id,
                             validator: ProjectValidator(), registry: .builtIn)
        #expect(store.records.isEmpty)
        #expect(store.lastError != nil)
    }

    @Test func cancelPassesThroughIdempotently() async throws {
        let project = try fixtureProject()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-runstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = CancelCounter()
        let store = RunStore(client: FakeRunClient(counter: counter), baseDirectory: directory)
        await store.submitL0(project: project, scenarioID: project.scenarios[0].id,
                             validator: ProjectValidator(), registry: .builtIn)
        let record = try #require(store.records.first)
        try await store.cancel(record)
        try await store.cancel(record)
        #expect(counter.count == 2)
    }
}
