import Foundation
import SimuCore

/// Snapshot-aware L2 (OpenFOAM steady field) runner. Process details stay in
/// the macOS adapter; iOS never sees Process or engine paths.
public protocol L2TaskClient: Sendable {
    nonisolated var isConfigured: Bool { get }
    func submitL2(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt
    func cancel(runID: UUID) async throws
    func loadResult(runID: UUID) async throws -> SimulationResult?
    /// Quality-passed runs write a seat-height temperature slice; quality
    /// failed runs write none, and loading returns nil instead of a fake field.
    func loadFieldSlice(runID: UUID) async throws -> FieldSlice?
    /// Quality-passed runs may also write glyphs and streamlines. Missing
    /// file or failed quality returns nil; nothing is sketched in.
    func loadFlowOverlay(runID: UUID) async throws -> FlowOverlay?
    func loadEvents(runID: UUID) async throws -> [SimulationEvent]
}

/// Default App client. Never fabricates fields, comfort metrics or slices.
public struct UnconfiguredL2TaskClient: L2TaskClient {
    public nonisolated let isConfigured = false

    public init() {}

    public func submitL2(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt {
        throw SimulationClientError.engineNotConfigured
    }

    public func cancel(runID: UUID) async throws {
        throw SimulationClientError.engineNotConfigured
    }

    public func loadResult(runID: UUID) async throws -> SimulationResult? {
        nil
    }

    public func loadFieldSlice(runID: UUID) async throws -> FieldSlice? {
        nil
    }

    public func loadFlowOverlay(runID: UUID) async throws -> FlowOverlay? {
        nil
    }

    public func loadEvents(runID: UUID) async throws -> [SimulationEvent] {
        []
    }
}
