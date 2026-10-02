import Foundation

public enum SimulationFidelity: String, Codable, CaseIterable, Sendable {
    case l0, l1, l2, l3
}

public enum RunState: String, Codable, Sendable {
    case queued, validating, meshing, solving, postprocessing, checking
    case succeeded, failed, cancelled
}

public enum QualityState: String, Codable, Sendable {
    case notEvaluated, passed, failed
}

public enum ResultFreshness: String, Codable, Sendable {
    case current, stale
}

/// Immutable identity for one physical input snapshot. Hash generation is a future adapter.
public struct RunIdentity: Codable, Equatable, Sendable {
    public let runID: UUID
    public let scenarioID: UUID
    public let inputHash: String

    public init(runID: UUID = UUID(), scenarioID: UUID, inputHash: String) {
        self.runID = runID
        self.scenarioID = scenarioID
        self.inputHash = inputHash
    }

    public func freshness(relativeTo currentInputHash: String) -> ResultFreshness {
        inputHash == currentInputHash ? .current : .stale
    }
}

/// Numerical outputs are intentionally absent until real engines are integrated.
public struct RunReceipt: Codable, Equatable, Sendable {
    public let identity: RunIdentity
    public let state: RunState
    public let quality: QualityState

    public init(identity: RunIdentity, state: RunState, quality: QualityState = .notEvaluated) {
        self.identity = identity
        self.state = state
        self.quality = quality
    }
}
