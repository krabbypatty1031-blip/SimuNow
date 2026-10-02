import Foundation
import SimuCore

/// A fixed, display-ready snapshot for one report. All values are pre-formatted by the
/// caller (Workspace); Reporting never recomputes metrics (P5 evidence rule).
public struct ReportContent: Equatable, Sendable {
    public struct MetricLine: Equatable, Sendable {
        public let title: String
        /// Formatted value with unit, or "缺失：原因". Never "0" for missing.
        public let value: String
        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    public struct Entry: Equatable, Sendable {
        public let scenarioName: String
        public let runID: String
        public let inputHash: String
        public let fidelity: String
        public let quality: String
        public let representativeDate: String?
        public let metrics: [MetricLine]
        public let assumptions: [String]
        /// Quotes and tariff notes; "待报价" entries instead of zeros.
        public let costLines: [String]

        public init(scenarioName: String, runID: String, inputHash: String, fidelity: String,
                    quality: String, representativeDate: String?, metrics: [MetricLine],
                    assumptions: [String], costLines: [String]) {
            self.scenarioName = scenarioName
            self.runID = runID
            self.inputHash = inputHash
            self.fidelity = fidelity
            self.quality = quality
            self.representativeDate = representativeDate
            self.metrics = metrics
            self.assumptions = assumptions
            self.costLines = costLines
        }
    }

    public struct CardLine: Equatable, Sendable {
        public let title: String
        public let body: String
        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public let projectName: String
    public let generatedAt: Date
    /// Scope and caliber statements shown before any numbers.
    public let scopeStatements: [String]
    public let entries: [Entry]
    public let cards: [CardLine]
    public let unknownsAndAssumptions: [String]
    public let limitations: [String]

    public init(projectName: String, generatedAt: Date, scopeStatements: [String], entries: [Entry],
                cards: [CardLine], unknownsAndAssumptions: [String], limitations: [String]) {
        self.projectName = projectName
        self.generatedAt = generatedAt
        self.scopeStatements = scopeStatements
        self.entries = entries
        self.cards = cards
        self.unknownsAndAssumptions = unknownsAndAssumptions
        self.limitations = limitations
    }
}

/// A report references only completed, quality-passed, current runs; the caller enforces
/// eligibility when building ReportContent. Enforcement of export gating lives in the exporter.
public protocol ReportExporter: Sendable {
    func export(_ content: ReportContent, to destination: URL) async throws
}
