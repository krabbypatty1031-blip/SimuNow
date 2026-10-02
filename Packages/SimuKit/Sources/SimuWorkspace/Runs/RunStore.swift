import Foundation
import SimuCore
import SimuSimulation

public enum RunStatus: Equatable, Sendable {
    case running, completed, failed, cancelled
    /// Run directory exists but no result: the app was interrupted before completion.
    case interrupted

    public var title: String {
        switch self {
        case .running: "进行中"
        case .completed: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        case .interrupted: "已中断"
        }
    }
}

/// One run as seen by the app: identity, live event tail, terminal result, freshness axis.
/// A record never mutates another run's directory.
public struct RunRecord: Identifiable, Equatable, Sendable {
    public let identity: RunIdentity
    public let fidelity: SimulationFidelity
    public var status: RunStatus
    public var events: [RunEvent]
    public var result: RunResult?
    public var errorMessage: String?
    public let runDirectory: URL
    public let startedAt: Date?

    public var id: UUID { identity.runID }

    public func freshness(relativeTo currentInputHash: String?) -> ResultFreshness {
        guard let currentInputHash else { return .stale }
        return identity.freshness(relativeTo: currentInputHash)
    }
}

/// Tracks runs for the open project. Terminal, quality and freshness stay independent axes;
/// only current, quality-passed results may feed recommendations (P5 enforces).
@MainActor
@Observable
public final class RunStore {
    /// Fraction of the event log kept in memory for display.
    public static let eventTailCount = 200

    public private(set) var records: [RunRecord] = []
    public private(set) var currentHashes: [UUID: String] = [:]
    public private(set) var lastError: String?
    public let client: any RunClient
    public let baseDirectory: URL

    public init(client: any RunClient, baseDirectory: URL? = nil) {
        self.client = client
        self.baseDirectory = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SimuNow/Runs", isDirectory: true)
    }

    public func records(for scenarioID: UUID) -> [RunRecord] {
        records.filter { $0.identity.scenarioID == scenarioID }
    }

    public func latest(for scenarioID: UUID) -> RunRecord? {
        records(for: scenarioID).first
    }

    public func currentHash(for scenarioID: UUID) -> String? { currentHashes[scenarioID] }

    /// Clear all in-memory state (project closed).
    public func reset() {
        records = []
        currentHashes = [:]
        lastError = nil
    }

    // MARK: - Freshness

    /// Recompute the per-scenario input hashes after an edit. Old results are never deleted;
    /// their identity hash simply stops matching, which marks them stale.
    public func syncHashes(project: ProjectDocument) {
        var hashes: [UUID: String] = [:]
        for scenario in project.scenarios {
            if let snapshot = try? ScenarioSnapshotBuilder.capture(project, scenarioID: scenario.id),
               let hash = try? InputHash.snapshotHash(snapshot) {
                hashes[scenario.id] = hash
            }
        }
        currentHashes = hashes
    }

    // MARK: - Submit / cancel

    /// Submit an L0 run for a scenario. The caller gates on inputPreparation; the store
    /// double-checks so an unvalidated project can never reach the worker.
    public func submitL0(project: ProjectDocument, scenarioID: UUID, validator: ProjectValidator, registry: ModelRegistry) async {
        lastError = nil
        do {
            let report = try validator.validate(project, registry: registry)
            guard report.passes(.inputPreparation) else {
                lastError = "输入校验未通过：先在校验列表中解决阻断项。"
                return
            }
            let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID)
            let input = try RunInput(fidelity: .l0, snapshot: snapshot)
            let runDirectory = baseDirectory
                .appendingPathComponent(project.id.uuidString, isDirectory: true)
                .appendingPathComponent(scenarioID.uuidString, isDirectory: true)
                .appendingPathComponent(input.identity.runID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            try input.encoded().write(to: runDirectory.appendingPathComponent("input.json"))
            let job = RunJob(identity: input.identity, fidelity: .l0, runDirectoryURL: runDirectory)
            let record = RunRecord(identity: input.identity, fidelity: .l0, status: .running,
                                   events: [], result: nil, errorMessage: nil,
                                   runDirectory: runDirectory, startedAt: Date())
            records.insert(record, at: 0)
            await streamEvents(job: job)
        } catch {
            lastError = "提交失败：\(error.localizedDescription)"
        }
    }

    private func streamEvents(job: RunJob) async {
        do {
            for try await event in client.events(for: job) {
                appendEvent(event, to: job.identity.runID)
            }
            finishFromDisk(job: job)
        } catch {
            markFailed(job: job, message: String(describing: error))
        }
    }

    public func cancel(_ record: RunRecord) async {
        let job = RunJob(identity: record.identity, fidelity: record.fidelity, runDirectoryURL: record.runDirectory)
        do {
            try await client.cancel(job)
        } catch {
            lastError = "取消失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Record updates

    private func appendEvent(_ event: RunEvent, to runID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == runID }) else { return }
        records[index].events.append(event)
        if records[index].events.count > Self.eventTailCount {
            records[index].events.removeFirst(records[index].events.count - Self.eventTailCount)
        }
        switch event.eventType {
        case .completed: records[index].status = .completed
        case .failed: records[index].status = .failed
        case .cancelled: records[index].status = .cancelled
        default: break
        }
    }

    private func finishFromDisk(job: RunJob) {
        guard let index = records.firstIndex(where: { $0.id == job.identity.runID }) else { return }
        let resultURL = job.runDirectoryURL.appendingPathComponent("result.json")
        if let data = FileManager.default.contents(atPath: resultURL.path),
           let result = try? RunResult.load(from: data) {
            records[index].result = result
            records[index].status = switch result.state {
            case .completed: .completed
            case .failed: .failed
            case .cancelled: .cancelled
            }
            if let error = result.error { records[index].errorMessage = error.message }
        }
    }

    private func markFailed(job: RunJob, message: String) {
        guard let index = records.firstIndex(where: { $0.id == job.identity.runID }) else { return }
        records[index].status = .failed
        records[index].errorMessage = message
    }

    // MARK: - Disk recovery

    /// Rebuild records from run directories. Dirs without result.json are interrupted runs.
    public func loadFromDisk(projectID: UUID) {
        records = []
        let projectDir = baseDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard let scenarioDirs = try? FileManager.default.contentsOfDirectory(
            at: projectDir, includingPropertiesForKeys: nil) else { return }
        var restored: [RunRecord] = []
        for scenarioDir in scenarioDirs {
            guard let runDirs = try? FileManager.default.contentsOfDirectory(
                at: scenarioDir, includingPropertiesForKeys: nil) else { continue }
            for runDir in runDirs {
                guard let record = restore(runDir: runDir) else { continue }
                restored.append(record)
            }
        }
        records = restored.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    private func restore(runDir: URL) -> RunRecord? {
        let inputURL = runDir.appendingPathComponent("input.json")
        guard let inputData = FileManager.default.contents(atPath: inputURL.path),
              let node = try? JSONValue(data: inputData),
              let runIDText = node["runID"]?.string, let runID = UUID(uuidString: runIDText),
              let scenarioText = node["scenarioID"]?.string, let scenarioID = UUID(uuidString: scenarioText),
              let hash = node["inputHash"]?.string,
              let fidelityText = node["fidelity"]?.string, let fidelity = SimulationFidelity(rawValue: fidelityText) else {
            return nil
        }
        let identity = RunIdentity(runID: runID, scenarioID: scenarioID, inputHash: hash)
        var events: [RunEvent] = []
        var integrityError: String?
        if let eventsData = FileManager.default.contents(atPath: runDir.appendingPathComponent("events.jsonl").path) {
            var parser = RunEventStreamParser(expectedRunID: runID)
            do {
                events = try parser.push(eventsData) + parser.finish()
            } catch {
                integrityError = "事件流校验失败：\(error)"
                events = []
            }
        }
        var result: RunResult?
        if let resultData = FileManager.default.contents(atPath: runDir.appendingPathComponent("result.json").path) {
            result = try? RunResult.load(from: resultData)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        var startedAt: Date? = nil
        if let text = result?.startedAt { startedAt = Self.isoDate(text) }
        if startedAt == nil { startedAt = attributes?[.creationDate] as? Date }
        let status: RunStatus
        var errorMessage = integrityError
        if let result {
            status = switch result.state {
            case .completed: .completed
            case .failed: .failed
            case .cancelled: .cancelled
            }
            if let error = result.error { errorMessage = error.message }
        } else {
            status = .interrupted
        }
        return RunRecord(identity: identity, fidelity: fidelity, status: status,
                         events: Array(events.suffix(Self.eventTailCount)), result: result,
                         errorMessage: errorMessage, runDirectory: runDir, startedAt: startedAt)
    }

    private static func isoDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
