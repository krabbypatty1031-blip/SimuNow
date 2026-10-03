import Foundation

/// Fixed evidence. A suggestion never edits the project or upgrades rule previews to measurements.
public struct SuggestionCard: Codable, Equatable, Sendable, Identifiable {
    public let identity: RunIdentity
    public let ruleID: String
    public let ruleVersion: Int
    public let seatID: UUID
    public let sampleID: UUID?
    public let obstacleID: UUID?
    public let profileID: String
    public let profileVersion: Int
    public let relation: PreviewRelationState
    public let message: String
    public var id: String { "\(identity.runID)/\(seatID)/\(sampleID?.uuidString ?? "position")/\(ruleID)" }
    public init(identity: RunIdentity, ruleID: String, ruleVersion: Int = 1, seatID: UUID,
                sampleID: UUID?, obstacleID: UUID?, profileID: String, profileVersion: Int,
                relation: PreviewRelationState, message: String) {
        self.identity = identity; self.ruleID = ruleID; self.ruleVersion = ruleVersion
        self.seatID = seatID; self.sampleID = sampleID; self.obstacleID = obstacleID
        self.profileID = profileID; self.profileVersion = profileVersion; self.relation = relation; self.message = message
    }
}

public struct ComparisonEvidenceReference: Codable, Equatable, Sendable {
    public let run: ComparisonRunReference
    public let inputSHA256: String
    public let resultSHA256: String
    public init(run: ComparisonRunReference, inputSHA256: String, resultSHA256: String) {
        self.run = run; self.inputSHA256 = inputSHA256; self.resultSHA256 = resultSHA256
    }
}

/// The hash covers the canonical body with bodyHash omitted. Old apps preserve this sidefile opaquely.
public struct ComparisonRecord: Codable, Equatable, Sendable, Identifiable {
    public let recordVersion: Int
    public let owner: String
    public let snapshot: ComparisonSnapshot
    public let references: [ComparisonEvidenceReference]
    public let bodyHash: String
    public var id: UUID { snapshot.comparisonID }
    public init(snapshot: ComparisonSnapshot, references: [ComparisonEvidenceReference], bodyHash: String) {
        recordVersion = 1; owner = "com.simunow.comparison"
        self.snapshot = snapshot; self.references = references; self.bodyHash = bodyHash
    }
}

public struct ReportRunSummary: Codable, Equatable, Sendable {
    public let reference: ComparisonRunReference
    public let scenarioAlias: String
    public let basis: AnalysisResultBasis
    public let checks: AnalysisChecksState
    public let historical: Bool
    public let lines: [String]
    public let assumptions: [String]
    public let missingReasons: [String]
    public init(reference: ComparisonRunReference, scenarioAlias: String, basis: AnalysisResultBasis,
                checks: AnalysisChecksState, historical: Bool, lines: [String], assumptions: [String], missingReasons: [String]) {
        self.reference = reference; self.scenarioAlias = scenarioAlias; self.basis = basis
        self.checks = checks; self.historical = historical; self.lines = lines
        self.assumptions = assumptions; self.missingReasons = missingReasons
    }
}

/// A deliberately redacted, frozen summary, never a replacement for the full run input.
public struct LocalReportSnapshot: Codable, Equatable, Sendable {
    public let reportVersion: Int
    public let reportID: UUID
    public let createdAt: Date
    public let runs: [ReportRunSummary]
    public let comparison: ComparisonSnapshot?
    public let redactedFields: [String]
    public let limitations: [String]
    public init(reportID: UUID = UUID(), createdAt: Date = Date(), runs: [ReportRunSummary], comparison: ComparisonSnapshot? = nil) {
        reportVersion = 1; self.reportID = reportID; self.createdAt = createdAt
        self.runs = runs; self.comparison = comparison
        redactedFields = ["projectName", "scenarioNames", "seatNames", "geometry", "photos", "privateSourceReferences", "sourceFreeText"]
        limitations = ["规则路径是几何假设，不是真实风速、CFD 或舒适评价。", "显热与用电仅对应声明时段及输入情景，不能推算全年节能。", "本摘要已删减；原 inputHash 用于追溯，不能从匿名摘要重算完整输入哈希。"]
    }
}
