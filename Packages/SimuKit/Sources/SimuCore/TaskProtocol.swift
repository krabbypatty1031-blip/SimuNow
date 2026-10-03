import CryptoKit
import Foundation

/// Structured failures for the P3 task wire format. Not a solver error.
public enum TaskProtocolError: Error, Equatable, Sendable {
    case hashMismatch
    case unsafeSnapshotPath
    case staleSequence
    case truncatedLine
    case wrongRun
    case invalidJSON
}

public enum InputSnapshotHash {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Relative package path only. Absolute home/Desktop paths are sandbox-hostile and leak identity.
    public static func isSafeSnapshotPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("/") || trimmed.contains("://") { return false }
        if trimmed.split(separator: "/").contains("..") { return false }
        let lowered = trimmed.lowercased()
        if lowered.contains("/users/") || lowered.hasPrefix("users/") { return false }
        if lowered.contains("/downloads/") || lowered.contains("/desktop/") { return false }
        return true
    }
}

public enum SimulationEventType: String, Codable, Sendable {
    case accepted, progress, log, quality, completed, failed, cancelled
}

public struct SimulationEventPayload: Codable, Equatable, Sendable {
    public var fraction: Double?
    public var monitor: String?
    public var message: String?

    public init(fraction: Double? = nil, monitor: String? = nil, message: String? = nil) {
        self.fraction = fraction
        self.monitor = monitor
        self.message = message
    }
}

public struct SimulationEvent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runID: UUID
    public var scenarioID: UUID
    public var inputHash: String
    public var sequence: Int
    public var timestamp: String
    public var eventType: SimulationEventType
    public var stage: RunState
    public var payload: SimulationEventPayload?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, runID, scenarioID, inputHash, sequence, timestamp, eventType, stage, payload
    }

    public init(
        schemaVersion: Int = 1,
        runID: UUID,
        scenarioID: UUID,
        inputHash: String,
        sequence: Int,
        timestamp: String,
        eventType: SimulationEventType,
        stage: RunState,
        payload: SimulationEventPayload? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.scenarioID = scenarioID
        self.inputHash = inputHash
        self.sequence = sequence
        self.timestamp = timestamp
        self.eventType = eventType
        self.stage = stage
        self.payload = payload
    }
}

/// Incremental JSONL reader. Does not reorder events or invent progress.
public struct TaskEventStream: Equatable, Sendable {
    public let expectedRunID: UUID
    public private(set) var events: [SimulationEvent] = []
    private var buffer = ""

    public init(expectedRunID: UUID) {
        self.expectedRunID = expectedRunID
    }

    public mutating func ingest(_ chunk: String) throws -> [SimulationEvent] {
        buffer += chunk
        var accepted: [SimulationEvent] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            accepted.append(try accept(line: line))
        }
        return accepted
    }

    public mutating func finish() throws {
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TaskProtocolError.truncatedLine
        }
    }

    private mutating func accept(line: String) throws -> SimulationEvent {
        let event: SimulationEvent
        do {
            event = try JSONDecoder().decode(SimulationEvent.self, from: Data(line.utf8))
        } catch {
            throw TaskProtocolError.invalidJSON
        }
        if event.runID != expectedRunID {
            throw TaskProtocolError.wrongRun
        }
        if let last = events.last, event.sequence <= last.sequence {
            throw TaskProtocolError.staleSequence
        }
        events.append(event)
        return event
    }
}

public struct ResultMetric: Codable, Equatable, Sendable {
    public var name: String
    public var value: Double?
    public var unit: String
    public var method: String
    public var fidelity: SimulationFidelity
    public var omitted: Bool

    enum CodingKeys: String, CodingKey {
        case name, value, unit, method, fidelity, omitted
    }

    public init(
        name: String,
        value: Double?,
        unit: String,
        method: String,
        fidelity: SimulationFidelity,
        omitted: Bool
    ) {
        self.name = name
        self.value = omitted ? nil : value
        self.unit = unit
        self.method = method
        self.fidelity = fidelity
        self.omitted = omitted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        unit = try container.decode(String.self, forKey: .unit)
        method = try container.decode(String.self, forKey: .method)
        fidelity = try container.decode(SimulationFidelity.self, forKey: .fidelity)
        omitted = try container.decodeIfPresent(Bool.self, forKey: .omitted) ?? false
        let decodedValue = try container.decodeIfPresent(Double.self, forKey: .value)
        value = omitted ? nil : decodedValue
    }
}

public struct ResultPeriod: Codable, Equatable, Sendable {
    public var kind: String
    public var start: String
    public var end: String

    public init(kind: String, start: String, end: String) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

/// Numerical result for one run. Missing metrics stay nil; they are not 0.
public struct SimulationResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var identity: RunIdentity
    public var state: RunState
    public var quality: QualityState
    public var metrics: [ResultMetric]
    public var period: ResultPeriod?
    public var weatherPath: String?
    public var weatherHash: String?
    public var supplyTemperatureC: Double?
    public var setpointC: Double?
    public var schedule: ResultPeriod?
    public var hvacSchedule: ResultPeriod?
    public var scheduleHash: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, identity, state, quality, metrics
        case period, weatherPath, weatherHash, supplyTemperatureC, setpointC
        case schedule, hvacSchedule, scheduleHash
    }

    public init(
        schemaVersion: Int = 1,
        identity: RunIdentity,
        state: RunState,
        quality: QualityState,
        metrics: [ResultMetric],
        period: ResultPeriod? = nil,
        weatherPath: String? = nil,
        weatherHash: String? = nil,
        supplyTemperatureC: Double? = nil,
        setpointC: Double? = nil,
        schedule: ResultPeriod? = nil,
        hvacSchedule: ResultPeriod? = nil,
        scheduleHash: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.state = state
        self.quality = quality
        self.metrics = metrics
        self.period = period
        self.weatherPath = weatherPath
        self.weatherHash = weatherHash
        self.supplyTemperatureC = supplyTemperatureC
        self.setpointC = setpointC
        self.schedule = schedule
        self.hvacSchedule = hvacSchedule
        self.scheduleHash = scheduleHash
    }

    public func metric(named name: String) -> ResultMetric? {
        metrics.first { $0.name == name }
    }
}
