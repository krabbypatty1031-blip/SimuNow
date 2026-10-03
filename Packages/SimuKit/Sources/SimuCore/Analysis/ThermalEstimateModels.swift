import Foundation

public struct HeatBalanceCoverage: Codable, Equatable, Sendable {
    public let conductanceScope: String
    public let internalSensibleScope: String
    public let airPropertyConditions: String
    public let indoorConditionConfirmed: Bool
    public let source: SourceRecord
    public init(conductanceScope: String, internalSensibleScope: String, airPropertyConditions: String, indoorConditionConfirmed: Bool, source: SourceRecord) {
        self.conductanceScope = conductanceScope; self.internalSensibleScope = internalSensibleScope; self.airPropertyConditions = airPropertyConditions
        self.indoorConditionConfirmed = indoorConditionConfirmed; self.source = source
    }
}
public struct HeatInternalSource: Codable, Equatable, Sendable {
    public let entityID: UUID
    public let description: String
    public let sensible: ThermalPower
    public let effectiveFraction: Ratio
    public init(entityID: UUID, description: String, sensible: ThermalPower, effectiveFraction: Ratio) {
        self.entityID = entityID; self.description = description; self.sensible = sensible; self.effectiveFraction = effectiveFraction
    }
}
public struct HeatTermExclusion: Codable, Equatable, Sendable {
    public let term: String
    public let reason: String
    public init(term: String, reason: String) { self.term = term; self.reason = reason }
}
public enum HeatBalanceCompleteness: String, Codable, Sendable { case completeDeclaredCase, declaredSubset }
public struct HeatSensitivityConfiguration: Codable, Equatable, Sendable {
    public let fields: [String]
    public let relationship: String
    public let source: SourceRecord
    public init(fields: [String], relationship: String, source: SourceRecord) { self.fields = fields; self.relationship = relationship; self.source = source }
}
public struct HeatSensitivityValue: Codable, Equatable, Sendable {
    public let field: String
    public let value: Double
    public let unit: String
    public let source: SourceRecord
    public init(field: String, value: Double, unit: String, source: SourceRecord) { self.field = field; self.value = value; self.unit = unit; self.source = source }
}
public struct HeatSensitivityScenario: Codable, Equatable, Sendable {
    public let id: String
    public let adoptedValues: [HeatSensitivityValue]
    public let totalSignedWatts: Double
    public let coolingSensibleWatts: Double
    public init(id: String, adoptedValues: [HeatSensitivityValue], totalSignedWatts: Double, coolingSensibleWatts: Double) {
        self.id = id; self.adoptedValues = adoptedValues; self.totalSignedWatts = totalSignedWatts; self.coolingSensibleWatts = coolingSensibleWatts
    }
}
public struct CostTariffInterval: Codable, Equatable, Sendable {
    public let startMinute: Int
    public let endMinute: Int
    public let rate: EnergyRate
    public init(startMinute: Int, endMinute: Int, rate: EnergyRate) { self.startMinute = startMinute; self.endMinute = endMinute; self.rate = rate }
}
public struct CostEvaluationConfiguration: Codable, Equatable, Sendable {
    public let timeBasis: AnalysisTimeBasis
    public let requestedWindows: [AnalysisTimeWindow]
    public let currency: String?
    public let tariffs: [CostTariffInterval]
    public let displayFractionDigits: Int
    public let excludedCosts: [String]
    public init(timeBasis: AnalysisTimeBasis = .fixed24HourReference, requestedWindows: [AnalysisTimeWindow], currency: String?, tariffs: [CostTariffInterval], displayFractionDigits: Int = 2, excludedCosts: [String] = ["subscription", "equipment", "installation"]) {
        self.timeBasis = timeBasis; self.requestedWindows = requestedWindows; self.currency = currency; self.tariffs = tariffs
        self.displayFractionDigits = displayFractionDigits; self.excludedCosts = excludedCosts
    }
}
/// Base-10 strings preserve Decimal output without passing currency through JSON Double.
public struct CostEvaluationSegment: Codable, Equatable, Sendable {
    public let startMinute: Int
    public let endMinute: Int
    public let energyKWhDecimal: String
    public let rateDecimal: String
    public let costDecimal: String
    public let source: SourceRecord
    public init(startMinute: Int, endMinute: Int, energyKWhDecimal: String, rateDecimal: String, costDecimal: String, source: SourceRecord) {
        self.startMinute = startMinute; self.endMinute = endMinute; self.energyKWhDecimal = energyKWhDecimal; self.rateDecimal = rateDecimal
        self.costDecimal = costDecimal; self.source = source
    }
}
public struct CostEvaluationPayload: Codable, Equatable, Sendable {
    public let segments: [CostEvaluationSegment]
    public let totalCostDecimal: String?
    public let lowerCostDecimal: String?
    public let upperCostDecimal: String?
    public let missingReasons: [AnalysisMissingReason]
    public let decimalPolicy: String
    public init(segments: [CostEvaluationSegment], totalCostDecimal: String?, lowerCostDecimal: String? = nil, upperCostDecimal: String? = nil, missingReasons: [AnalysisMissingReason], decimalPolicy: String = "binary64 shortest round-trip decimal input; base-10 Decimal (38 significant digits); adopted power/rate inputs 0 or 1e-12...1e12; no per-segment display rounding") {
        self.segments = segments; self.totalCostDecimal = totalCostDecimal; self.lowerCostDecimal = lowerCostDecimal; self.upperCostDecimal = upperCostDecimal
        self.missingReasons = missingReasons; self.decimalPolicy = decimalPolicy
    }
}
public struct CostEvaluationRecord: Codable, Equatable, Sendable {
    public let evaluationVersion: Int
    public let owner: String
    public let projectID: UUID
    public let parentIdentity: RunIdentity
    public let evaluationHash: String
    public let configuration: CostEvaluationConfiguration
    public let payload: CostEvaluationPayload
    public init(projectID: UUID, parentIdentity: RunIdentity, evaluationHash: String, configuration: CostEvaluationConfiguration, payload: CostEvaluationPayload, evaluationVersion: Int = 1, owner: String = "com.simunow.native-analysis") {
        self.evaluationVersion = evaluationVersion; self.owner = owner; self.projectID = projectID; self.parentIdentity = parentIdentity
        self.evaluationHash = evaluationHash; self.configuration = configuration; self.payload = payload
    }
}
public struct EstimateComparisonMetric: Codable, Equatable, Sendable {
    public let metric: String
    public let unit: String
    public let baseline: Double?
    public let candidate: Double?
    public let absoluteDifference: Double?
    public let percentDifference: Double?
    public let reasons: [String]
    public let ranking: String
    public init(metric: String, unit: String, baseline: Double?, candidate: Double?, absoluteDifference: Double?, percentDifference: Double?, reasons: [String], ranking: String) {
        self.metric = metric; self.unit = unit; self.baseline = baseline; self.candidate = candidate; self.absoluteDifference = absoluteDifference
        self.percentDifference = percentDifference; self.reasons = reasons; self.ranking = ranking
    }
}
