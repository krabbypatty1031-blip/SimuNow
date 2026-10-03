#if os(macOS)
import Foundation
import SimuCore

/// macOS adapter for in-app L2. The OpenFOAM wrapper may wrap Docker; whether
/// Docker is reachable inside the App sandbox is discovered at run time, and a
/// failed run stays failed - no invented fields or comfort metrics.
public actor LocalProcessL2Client: L2TaskClient {
    public nonisolated let isConfigured: Bool
    private let inner: LocalProcessClient
    private let runRoot: URL

    public init(repositoryRoot: URL, enginesRoot: URL, runRoot: URL) {
        self.runRoot = runRoot
        // Hold the grant for the actor lifetime so the child Process can read
        // the staged worker tree and engines.
        _ = repositoryRoot.startAccessingSecurityScopedResource()
        _ = enginesRoot.startAccessingSecurityScopedResource()
        let inner = LocalProcessClient(
            repositoryRoot: repositoryRoot,
            runRoot: runRoot,
            extraEnvironment: ["SIMUNOW_ENGINES_ROOT": enginesRoot.path]
        )
        self.inner = inner
        // A startable interpreter plus the staged worker and wrapper bits.
        // Whether OpenFOAM truly runs stays the run's own evidence.
        self.isConfigured = inner.isUsable && Self.probeIsConfigured(
            repositoryRoot: repositoryRoot,
            enginesRoot: enginesRoot
        )
    }

    /// L2 needs the staged worker plus an executable OpenFOAM wrapper. File
    /// presence and POSIX execute bits only - actually launching OpenFOAM is
    /// the run's own evidence. X_OK probes are denied in the sandbox, so the
    /// bits come from stat.
    static func probeIsConfigured(repositoryRoot: URL, enginesRoot: URL) -> Bool {
        let worker = repositoryRoot.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
        let wrapper = enginesRoot.appendingPathComponent("openfoam.sh")
        return FileManager.default.fileExists(atPath: worker.path)
            && LocalEngineProbe.hasExecuteBit(at: wrapper.path)
    }

    public func submitL2(_ request: SimulationRequest, snapshot: Data) async throws -> RunReceipt {
        guard isConfigured else { throw SimulationClientError.engineNotConfigured }
        // L2 solves a steady field; give the wrapper far more headroom than L1.
        return try await inner.submit(
            request,
            snapshot: snapshot,
            timeoutSeconds: 900,
            workerCommand: "run-l2"
        )
    }

    public func cancel(runID: UUID) async throws {
        try await inner.cancel(runID: runID)
    }

    public func loadResult(runID: UUID) async throws -> SimulationResult? {
        try await inner.loadResult(runID: runID)
    }

    /// Read the quality-gated seat-height slice written by a passing run.
    /// Quality-failed runs have no slice file; return nil, never a fake field.
    public func loadFieldSlice(runID: UUID) async throws -> FieldSlice? {
        let url = runRoot
            .appendingPathComponent(runID.uuidString, isDirectory: true)
            .appendingPathComponent("field-slice.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(FieldSlice.self, from: Data(contentsOf: url))
    }

    /// Quality-failed runs have no flow file; return nil, never sketched arrows.
    public func loadFlowOverlay(runID: UUID) async throws -> FlowOverlay? {
        let url = runRoot
            .appendingPathComponent(runID.uuidString, isDirectory: true)
            .appendingPathComponent("field-flow.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(FlowOverlay.self, from: Data(contentsOf: url))
    }

    public func loadEvents(runID: UUID) async throws -> [SimulationEvent] {
        try await inner.loadEvents(runID: runID)
    }
}
#endif
