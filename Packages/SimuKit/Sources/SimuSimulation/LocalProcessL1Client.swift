#if os(macOS)
import Foundation
import SimuCore

/// macOS adapter: user-selected repo + engines, never a hardcoded Desktop path.
public actor LocalProcessL1Client: L1TaskClient {
    public nonisolated let isConfigured: Bool
    private let inner: LocalProcessClient
    private let repositoryRoot: URL
    private let enginesRoot: URL

    public init(repositoryRoot: URL, enginesRoot: URL, runRoot: URL) {
        self.repositoryRoot = repositoryRoot
        self.enginesRoot = enginesRoot
        // Hold the grant for the actor lifetime so the child Process can read EnergyPlus.
        _ = repositoryRoot.startAccessingSecurityScopedResource()
        _ = enginesRoot.startAccessingSecurityScopedResource()
        let inner = LocalProcessClient(
            repositoryRoot: repositoryRoot,
            runRoot: runRoot,
            extraEnvironment: ["SIMUNOW_ENGINES_ROOT": enginesRoot.path]
        )
        self.inner = inner
        // A startable interpreter plus present engine files. Whether the
        // engine truly runs stays the run's own evidence.
        self.isConfigured = inner.isUsable && LocalEngineProbe.isConfigured(
            repositoryRoot: repositoryRoot,
            enginesRoot: enginesRoot
        )
    }

    public func submitL1(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt {
        guard isConfigured else { throw SimulationClientError.engineNotConfigured }
        return try await inner.submit(request, snapshot: snapshot)
    }

    public func cancel(runID: UUID) async throws {
        try await inner.cancel(runID: runID)
    }

    public func loadResult(runID: UUID) async throws -> SimulationResult? {
        try await inner.loadResult(runID: runID)
    }

    public func loadEvents(runID: UUID) async throws -> [SimulationEvent] {
        try await inner.loadEvents(runID: runID)
    }
}
#endif
