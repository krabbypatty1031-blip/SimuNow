import Foundation
import SimuCore

/// Snapshot-aware L1 runner. Process details stay in the macOS adapter.
public protocol L1TaskClient: Sendable {
    nonisolated var isConfigured: Bool { get }
    func submitL1(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt
    func cancel(runID: UUID) async throws
    func loadResult(runID: UUID) async throws -> SimulationResult?
    func loadEvents(runID: UUID) async throws -> [SimulationEvent]
}

/// Default App client. Never invents cooling watts.
public struct UnconfiguredL1TaskClient: L1TaskClient {
    public nonisolated let isConfigured = false

    public init() {}

    public func submitL1(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt {
        throw SimulationClientError.engineNotConfigured
    }

    public func cancel(runID: UUID) async throws {
        throw SimulationClientError.engineNotConfigured
    }

    public func loadResult(runID: UUID) async throws -> SimulationResult? {
        nil
    }

    public func loadEvents(runID: UUID) async throws -> [SimulationEvent] {
        []
    }
}
