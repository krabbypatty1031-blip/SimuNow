import Foundation

/// Review of pinned candidates. Every pin stays in the list; a basis
/// mismatch is a warning, never a silent drop that would make the remaining
/// pair look like a valid comparison.
public struct CandidateReview: Equatable, Sendable {
    public var candidates: [CandidateRun]
    public var basisWarning: String?

    public init(candidates: [CandidateRun], basisWarning: String? = nil) {
        self.candidates = candidates
        self.basisWarning = basisWarning
    }
}

/// Geometry axis versus comparison basis. L0 search is not configured here.
public enum DecisionVariables: Sendable {
    /// Supply/return placement. Changing these keeps the same people, hours and setpoints.
    public static let geometryPaths: [String] = [
        "hvac.supply.wall",
        "hvac.supply.s0",
        "hvac.supply.s1",
        "hvac.supply.z0",
        "hvac.supply.z1",
        "hvac.returnTerminal.wall",
        "hvac.returnTerminal.s0",
        "hvac.returnTerminal.s1",
        "hvac.returnTerminal.z0",
        "hvac.returnTerminal.z1"
    ]

    /// People, occupied hours and temperatures. A change here is a new basis.
    public static let basisPaths: [String] = [
        "occupancy.occupantCount",
        "occupancy.schedule",
        "hvac.setpointC",
        "hvac.supplyTemperatureC"
    ]

    /// Keep every pinned candidate. The first mismatch against the lead
    /// candidate is the warning text; later mismatches stay visible in the list.
    public static func review(_ candidates: [CandidateRun]) -> CandidateReview {
        guard let lead = candidates.first else {
            return CandidateReview(candidates: [])
        }
        var warning: String?
        for other in candidates.dropFirst() {
            if let mismatch = CandidateRun.basisMismatch(lead.basis, other.basis) {
                warning = mismatch
                break
            }
        }
        return CandidateReview(candidates: candidates, basisWarning: warning)
    }
}
