import Foundation
import SimuCore

// MARK: - Run events (run-event/1)

public enum RunEventType: String, Codable, CaseIterable, Sendable {
    case accepted, progress, log, quality, completed, failed, cancelled

    public var isTerminal: Bool { Self.terminal.contains(self) }
    private static let terminal: Set<RunEventType> = [.completed, .failed, .cancelled]
}

/// One validated line of the worker JSONL stream (Protocols/run-events-v1.md).
public struct RunEvent: Equatable, Sendable {
    public static let protocolID = "run-event/1"

    public let runID: UUID
    public let sequence: Int
    public let timestamp: String
    public let eventType: RunEventType
    public let stage: String?
    public let payload: JSONValue?

    public init(node: JSONValue) throws {
        guard let fields = node.fields else { throw RunProtocolError.invalidJSON("event is not an object") }
        guard fields["protocol"] == .string(Self.protocolID) else {
            throw RunProtocolError.wrongProtocol(fields["protocol"]?.string ?? "missing")
        }
        guard let runIDText = fields["runID"]?.string, let runID = UUID(uuidString: runIDText) else {
            throw RunProtocolError.missingField("runID")
        }
        guard let token = fields["sequence"], let number = token.double, let sequence = Int(exactly: number) else {
            throw RunProtocolError.missingField("sequence")
        }
        guard let timestamp = fields["timestamp"]?.string else { throw RunProtocolError.missingField("timestamp") }
        guard let typeText = fields["eventType"]?.string, let eventType = RunEventType(rawValue: typeText) else {
            throw RunProtocolError.unknownEventType(fields["eventType"]?.string ?? "missing")
        }
        self.runID = runID
        self.sequence = sequence
        self.timestamp = timestamp
        self.eventType = eventType
        self.stage = fields["stage"]?.string
        self.payload = fields["payload"]
    }
}

public enum RunProtocolError: Error, Equatable, Sendable {
    case invalidJSON(String)
    case wrongProtocol(String)
    case missingField(String)
    case wrongRun(expected: UUID, actual: UUID)
    case sequenceViolation(expected: Int, actual: Int)
    case unknownEventType(String)
    case truncatedStream
}

/// Incremental JSONL parser enforcing the client rejection rules: matching runID,
/// contiguous strictly increasing sequence (a gap means truncation), known event types.
/// Unknown optional fields and free-form payloads pass through.
public struct RunEventStreamParser: Sendable {
    public let expectedRunID: UUID
    private var buffer = Data()
    private var nextSequence = 1

    public init(expectedRunID: UUID) {
        self.expectedRunID = expectedRunID
    }

    public mutating func push(_ chunk: Data) throws -> [RunEvent] {
        buffer.append(chunk)
        var events: [RunEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer = buffer.suffix(from: buffer.index(after: newline))
            if let event = try parseLine(Data(line)) { events.append(event) }
        }
        return events
    }

    /// Flush at end of stream. A non-empty remainder is a truncated final line.
    public mutating func finish() throws -> [RunEvent] {
        defer { buffer = Data() }
        guard !buffer.isEmpty else { return [] }
        guard let event = try parseLine(buffer) else { return [] }
        return [event]
    }

    private mutating func parseLine(_ line: Data) throws -> RunEvent? {
        guard !line.isEmpty, line.contains(where: { $0 != 0x20 && $0 != 0x0D && $0 != 0x09 }) else { return nil }
        let node: JSONValue
        do {
            node = try JSONValue(data: line)
        } catch {
            throw RunProtocolError.invalidJSON("line is not valid JSON")
        }
        let event = try RunEvent(node: node)
        guard event.runID == expectedRunID else {
            throw RunProtocolError.wrongRun(expected: expectedRunID, actual: event.runID)
        }
        guard event.sequence == nextSequence else {
            throw RunProtocolError.sequenceViolation(expected: nextSequence, actual: event.sequence)
        }
        nextSequence += 1
        return event
    }
}

// MARK: - Run result (run-result/1)

public enum RunTerminalState: String, Codable, Sendable {
    case completed, failed, cancelled
}

public struct RunErrorDetail: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String
    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// One metric line. `value == nil` means missing; missingReason then explains why. Missing is never zero.
public struct RunMetric: Equatable, Sendable {
    public let name: String
    public let value: JSONValue?
    public let unit: String
    public let missingReason: String?
    public let aggregation: String
    public let method: String
    public let fidelity: String

    public init(name: String, value: JSONValue?, unit: String, missingReason: String? = nil,
                aggregation: String, method: String, fidelity: String) {
        self.name = name
        self.value = value
        self.unit = unit
        self.missingReason = missingReason
        self.aggregation = aggregation
        self.method = method
        self.fidelity = fidelity
    }

    public var isMissing: Bool { value == nil || value == .null }
    public var doubleValue: Double? { value?.double }
    public var boolValue: Bool? { if case .bool(let b) = value { return b }; return nil }
}

extension RunMetric: Codable {
    enum CodingKeys: String, CodingKey {
        case name, value, unit, aggregation, method, fidelity
        case missingReason = "missing_reason"
    }
}

public struct RunQuality: Equatable, Sendable, Codable {
    public let state: QualityState
    /// Free-form check entries; `name`/`state` keys are guaranteed by the schema.
    public let checks: [JSONValue]
    public init(state: QualityState, checks: [JSONValue]) {
        self.state = state
        self.checks = checks
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(QualityState.self, forKey: .state)
        checks = try c.decode([JSONValue].self, forKey: .checks)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encode(checks, forKey: .checks)
    }
    private enum CodingKeys: String, CodingKey { case state, checks }
}

/// The atomically written `<runDir>/result.json` (Protocols/run-events-v1.md).
public struct RunResult: Equatable, Sendable {
    public static let protocolID = "run-result/1"

    public let identity: RunIdentity
    public let fidelity: SimulationFidelity
    public let state: RunTerminalState
    public let metrics: [RunMetric]
    public let quality: RunQuality
    public let assumptions: [String]
    public let startedAt: String
    public let finishedAt: String?
    public let error: RunErrorDetail?

    public init(identity: RunIdentity, fidelity: SimulationFidelity, state: RunTerminalState,
                metrics: [RunMetric], quality: RunQuality, assumptions: [String],
                startedAt: String, finishedAt: String?, error: RunErrorDetail? = nil) {
        self.identity = identity
        self.fidelity = fidelity
        self.state = state
        self.metrics = metrics
        self.quality = quality
        self.assumptions = assumptions
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.error = error
    }

    public static func load(from data: Data) throws -> RunResult {
        let node = try JSONValue(data: data)
        guard node["protocol"] == .string(protocolID) else {
            throw RunProtocolError.wrongProtocol(node["protocol"]?.string ?? "missing")
        }
        return try JSONTreeCoding.decode(RunResult.self, from: node)
    }

    public func metric(named name: String) -> RunMetric? { metrics.first { $0.name == name } }
}

extension RunResult: Codable {
    enum CodingKeys: String, CodingKey {
        case identity, fidelity, state, metrics, quality, assumptions, startedAt, finishedAt, error
        case protocolMarker = "protocol"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identity = try c.decode(RunIdentity.self, forKey: .identity)
        fidelity = try c.decode(SimulationFidelity.self, forKey: .fidelity)
        state = try c.decode(RunTerminalState.self, forKey: .state)
        metrics = try c.decode([RunMetric].self, forKey: .metrics)
        quality = try c.decode(RunQuality.self, forKey: .quality)
        assumptions = try c.decode([String].self, forKey: .assumptions)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(String.self, forKey: .finishedAt)
        error = try c.decodeIfPresent(RunErrorDetail.self, forKey: .error)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.protocolID, forKey: .protocolMarker)
        try c.encode(identity, forKey: .identity)
        try c.encode(fidelity, forKey: .fidelity)
        try c.encode(state, forKey: .state)
        try c.encode(metrics, forKey: .metrics)
        try c.encode(quality, forKey: .quality)
        try c.encode(assumptions, forKey: .assumptions)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try c.encodeIfPresent(error, forKey: .error)
    }
}

// MARK: - Run input (run-input/1)

/// The immutable request handed to the worker (Protocols/run-input-v1.md). Identity fields
/// must match the snapshot; `inputHash` is InputHash.snapshotHash(snapshot).
public struct RunInput: Sendable {
    public static let protocolID = "run-input/1"

    public let identity: RunIdentity
    public let fidelity: SimulationFidelity
    public let snapshot: ScenarioInputSnapshot

    public init(fidelity: SimulationFidelity, snapshot: ScenarioInputSnapshot, runID: UUID = UUID()) throws {
        let hash = try InputHash.snapshotHash(snapshot)
        self.identity = RunIdentity(runID: runID, scenarioID: snapshot.scenarioID, inputHash: hash)
        self.fidelity = fidelity
        self.snapshot = snapshot
    }

    public func encoded() throws -> Data {
        let node: JSONValue = .object([
            "protocol": .string(Self.protocolID),
            "runID": .string(identity.runID.uuidString.uppercased()),
            "scenarioID": .string(identity.scenarioID.uuidString.uppercased()),
            "inputHash": .string(identity.inputHash),
            "fidelity": .string(fidelity.rawValue),
            "snapshot": try JSONTreeCoding.encode(snapshot),
        ])
        return try node.data()
    }
}
