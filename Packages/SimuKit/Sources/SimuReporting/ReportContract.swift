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

/// DeepSeek writes the readable body. Network or key failure does not invent a stand-in PDF.
public struct EvidenceReportExporter: ReportExporter {
    public var generator: (any ReportGenerator)?

    public init(generator: (any ReportGenerator)? = nil) {
        self.generator = generator
    }

    public func export(_ request: ReportRequest, to destination: URL) async throws {
        guard let generator else {
            throw EvidencePDFError.generatorUnavailable
        }
        guard let report = await generator.generate(request.evidence) else {
            throw EvidencePDFError.generatorUnavailable
        }
        try EvidencePDFAssembler.write(
            evidence: request.evidence,
            report: report,
            to: destination
        )
    }
}
