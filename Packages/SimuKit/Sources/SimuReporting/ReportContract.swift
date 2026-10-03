import Foundation
import SimuCore

/// A report may reference only a frozen evidence pack. The exporter does not reread the live draft.
public struct ReportRequest: Sendable {
    public let projectID: UUID
    public let runIDs: [UUID]
    public let evidence: ReportEvidence

    public init(projectID: UUID, runIDs: [UUID], evidence: ReportEvidence) {
        self.projectID = projectID
        self.runIDs = runIDs
        self.evidence = evidence
    }
}

public protocol ReportExporter: Sendable {
    func export(_ request: ReportRequest, to destination: URL) async throws
}

/// Evidence tables plus an optional narrator. Network or key failure still writes the tables.
public struct EvidenceReportExporter: ReportExporter {
    public var narrator: (any ReportNarrator)?

    public init(narrator: (any ReportNarrator)? = nil) {
        self.narrator = narrator
    }

    public func export(_ request: ReportRequest, to destination: URL) async throws {
        let narration = await narrator?.narrate(request.evidence)
        try EvidencePDFAssembler.write(
            evidence: request.evidence,
            narration: narration,
            to: destination
        )
    }
}
