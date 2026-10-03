import Foundation

public struct ProfessionalReviewConfiguration: Codable, Equatable, Sendable {
    public let configurationVersion: Int
    public let endpoint: String
    public let expectedEngine: String
    public let expectedVersion: String
    public let retentionPolicy: String
    public let maximumResponseBytes: Int
    public init(endpoint: String, expectedEngine: String, expectedVersion: String, retentionPolicy: String, maximumResponseBytes: Int = 2 * 1024 * 1024) {
        configurationVersion = 1; self.endpoint = endpoint; self.expectedEngine = expectedEngine
        self.expectedVersion = expectedVersion; self.retentionPolicy = retentionPolicy; self.maximumResponseBytes = maximumResponseBytes
    }
}
public struct ProfessionalReviewReceipt: Codable, Equatable, Sendable {
    public let receiptVersion: Int
    public let runID: UUID
    public let inputHash: String
    public let engine: String
    public let engineVersion: String
    public let qualityPassed: Bool
    public let benchmarkReference: String
    public let resultReference: String
    public init(runID: UUID, inputHash: String, engine: String, engineVersion: String, qualityPassed: Bool, benchmarkReference: String, resultReference: String) {
        receiptVersion = 1; self.runID = runID; self.inputHash = inputHash; self.engine = engine
        self.engineVersion = engineVersion; self.qualityPassed = qualityPassed
        self.benchmarkReference = benchmarkReference; self.resultReference = resultReference
    }
}
