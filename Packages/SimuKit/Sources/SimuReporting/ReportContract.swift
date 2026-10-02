import Foundation
import SimuCore

/// A report may reference only completed, quality-reviewed runs. Enforcement is planned in P5.
public struct ReportRequest: Sendable {
    public let projectID: UUID
    public let runIDs: [UUID]

    public init(projectID: UUID, runIDs: [UUID]) {
        self.projectID = projectID
        self.runIDs = runIDs
    }
}

public protocol ReportExporter: Sendable {
    func export(_ request: ReportRequest, to destination: URL) async throws
}
