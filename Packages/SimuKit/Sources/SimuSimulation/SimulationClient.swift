import Foundation
import SimuCore

public struct SimulationRequest: Codable, Equatable, Sendable {
    public let identity: RunIdentity
    public let fidelity: SimulationFidelity

    public init(identity: RunIdentity, fidelity: SimulationFidelity) {
        self.identity = identity
        self.fidelity = fidelity
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
