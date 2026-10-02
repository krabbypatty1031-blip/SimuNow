import Foundation

/// A fixed reference; comparison cannot silently substitute current edited inputs.
public struct ComparisonRunReference: Codable, Equatable, Sendable {
    public let runID: UUID
    public let scenarioID: UUID
    public let inputHash: String
    public let method: AnalysisMethod
    public let evaluationHash: String?
    public init(runID: UUID, scenarioID: UUID, inputHash: String, method: AnalysisMethod, evaluationHash: String? = nil) {
        self.runID = runID; self.scenarioID = scenarioID; self.inputHash = inputHash; self.method = method; self.evaluationHash = evaluationHash
    }
}
public struct ComparisonSnapshot: Codable, Equatable, Sendable {
    public let comparisonVersion: Int
    public let comparisonID: UUID
    public let projectID: UUID
    public let runs: [ComparisonRunReference]
    public let comparisonContextHash: String
    public let comparableItems: [String]
    public let incomparableReasons: [AnalysisMissingReason]
    public init(comparisonVersion: Int = 1, comparisonID: UUID = UUID(), projectID: UUID, runs: [ComparisonRunReference],
                comparisonContextHash: String, comparableItems: [String], incomparableReasons: [AnalysisMissingReason]) {
        self.comparisonVersion = comparisonVersion; self.comparisonID = comparisonID; self.projectID = projectID
        self.runs = runs; self.comparisonContextHash = comparisonContextHash; self.comparableItems = comparableItems; self.incomparableReasons = incomparableReasons
    }
}
public struct RecommendationEvidence: Codable, Equatable, Sendable {
    public let ruleID: String
    public let ruleVersion: Int
    public let runID: UUID
    public let entityID: UUID?
    public let fieldPath: String
    public let condition: String
    public let message: String
    public init(ruleID: String, ruleVersion: Int = 1, runID: UUID, entityID: UUID? = nil, fieldPath: String, condition: String, message: String) {
        self.ruleID = ruleID; self.ruleVersion = ruleVersion; self.runID = runID; self.entityID = entityID
        self.fieldPath = fieldPath; self.condition = condition; self.message = message
    }
}
