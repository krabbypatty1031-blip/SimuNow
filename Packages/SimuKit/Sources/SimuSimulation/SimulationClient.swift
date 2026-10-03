import Foundation
import SimuCore

public struct SimulationRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identity: RunIdentity
    public let fidelity: SimulationFidelity
    public let snapshotPath: String
    public let snapshotHash: String
    public let weatherPath: String?
    public let weatherHash: String?
    public let scheduleHash: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, identity, fidelity, snapshotPath, snapshotHash
        case weatherPath, weatherHash, scheduleHash
    }

    public init(
        identity: RunIdentity,
        fidelity: SimulationFidelity,
        snapshotPath: String,
        snapshotHash: String,
        weatherPath: String? = nil,
        weatherHash: String? = nil,
        scheduleHash: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.fidelity = fidelity
        self.snapshotPath = snapshotPath
        self.snapshotHash = snapshotHash
        self.weatherPath = weatherPath
        self.weatherHash = weatherHash
        self.scheduleHash = scheduleHash
    }

    /// Snapshot bytes must match both declared hashes. Path stays relative to the project package.
    public func validate(snapshot: Data) throws {
        guard InputSnapshotHash.isSafeSnapshotPath(snapshotPath) else {
            throw TaskProtocolError.unsafeSnapshotPath
        }
        if let weatherPath {
            guard InputSnapshotHash.isSafeSnapshotPath(weatherPath) else {
                throw TaskProtocolError.unsafeSnapshotPath
            }
        }
        let digest = InputSnapshotHash.sha256Hex(snapshot)
        guard digest == snapshotHash, digest == identity.inputHash else {
            throw TaskProtocolError.hashMismatch
        }
    }
}

/// Platform-neutral boundary. Process/container execution belongs in a macOS adapter.
public protocol SimulationClient: Sendable {
    func submit(_ request: SimulationRequest) async throws -> RunReceipt
    func cancel(runID: UUID) async throws
}

public enum SimulationClientError: Error, LocalizedError, Sendable {
    case engineNotConfigured

    public var errorDescription: String? {
        "计算引擎尚未配置，请按开发计划接入真实求解器。"
    }
}

/// Explicitly unavailable; never produces fabricated temperature, energy or comfort values.
public struct UnconfiguredSimulationClient: SimulationClient {
    public init() {}

    public func submit(_ request: SimulationRequest) async throws -> RunReceipt {
        throw SimulationClientError.engineNotConfigured
    }

    public func cancel(runID: UUID) async throws {
        throw SimulationClientError.engineNotConfigured
    }
}
