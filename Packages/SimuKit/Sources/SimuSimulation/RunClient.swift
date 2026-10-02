import Foundation
import SimuCore

/// Everything a run executor needs: the prepared input file, the run's own directory
/// and the cancellation marker path (Protocols/run-input-v1.md). A run writes only
/// inside its own directory.
public struct RunJob: Sendable {
    public let identity: RunIdentity
    public let fidelity: SimulationFidelity
    public let inputFileURL: URL
    public let runDirectoryURL: URL
    public let cancelFileURL: URL

    public init(identity: RunIdentity, fidelity: SimulationFidelity, runDirectoryURL: URL) {
        self.identity = identity
        self.fidelity = fidelity
        self.runDirectoryURL = runDirectoryURL
        self.inputFileURL = runDirectoryURL.appendingPathComponent("input.json")
        self.cancelFileURL = runDirectoryURL.appendingPathComponent("cancel-requested")
    }
}

public enum RunClientError: Error, Equatable, Sendable {
    /// No executor for this platform/configuration; the message names the remediation path.
    case unavailable(String)
    case workerCrashed(exitCode: Int32)
}

/// Streaming execution boundary. Process/container execution belongs in a macOS adapter
/// (LocalSimulationClient); iOS consumes file results or a future user-configured remote node.
public protocol RunClient: Sendable {
    /// Non-nil when this client cannot execute; the message names the remediation path.
    var unavailableReason: String? { get }
    /// Events arrive in wire order; the stream finishes after a terminal event and
    /// throws a RunProtocolError on out-of-order/wrong-run/unknown events.
    func events(for job: RunJob) -> AsyncThrowingStream<RunEvent, Error>
    /// Cooperative cancel via the marker file; idempotent. Hard process termination is the adapter's backstop.
    func cancel(_ job: RunJob) async throws
}

/// Explicitly unavailable executor. Never fabricates progress or results.
public struct UnavailableRunClient: RunClient {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public var unavailableReason: String? { reason }

    public func events(for job: RunJob) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: RunClientError.unavailable(reason))
        }
    }

    public func cancel(_ job: RunJob) async throws {
        throw RunClientError.unavailable(reason)
    }
}
