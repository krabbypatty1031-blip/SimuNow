import Foundation

public enum AnalysisKind: String, Codable, CaseIterable, Sendable {
    case airflowPreview, powerEstimate, steadyHeatBalance
}
public enum AnalysisResultBasis: String, Codable, Sendable { case rulePreview, simplifiedEstimate }
public struct AnalysisMethod: Codable, Equatable, Sendable {
    public let kind: AnalysisKind
    public let methodVersion: Int
    public var resultBasis: AnalysisResultBasis { kind == .airflowPreview ? .rulePreview : .simplifiedEstimate }
    public init(kind: AnalysisKind, methodVersion: Int = 1) { self.kind = kind; self.methodVersion = methodVersion }
}
public struct AnalysisAssumption: Codable, Equatable, Sendable {
    public let id: String
    public let version: Int
    public let source: SourceRecord
    public let meaning: String
    public init(id: String, version: Int = 1, source: SourceRecord, meaning: String) {
        self.id = id; self.version = version; self.source = source; self.meaning = meaning
    }
    public static let genericCone = Self(id: "simunow.preview.genericCone", source: .init(kind: .assumed, note: "Internal geometric display assumption, not measured airflow."),
        meaning: "Generic geometric cone for direction and obstruction preview; not measured airflow, velocity or comfort.")
}
public struct AnalysisResourceLimits: Codable, Equatable, Sendable {
    public let maximumPaths: Int
    public let maximumSegments: Int
    public let maximumObstacles: Int
    public let maximumTargets: Int
    public init(maximumPaths: Int = 64, maximumSegments: Int = 128, maximumObstacles: Int = 128, maximumTargets: Int = 512) {
        self.maximumPaths = maximumPaths; self.maximumSegments = maximumSegments
        self.maximumObstacles = maximumObstacles; self.maximumTargets = maximumTargets
    }
    public static let standard = Self()
}
public struct AirflowPreviewConfiguration: Codable, Equatable, Sendable {
    public let profileID: String
    public let profileVersion: Int
    public let baseRadiusMeters: Double
    public let halfAngleDegrees: Double
    public let lengthMeters: Double?
    public let pathCount: Int
    public let maximumSegments: Int
    public let seed: UInt32
    public let minimumStrength: Double
    public let source: SourceRecord
    /// Explicitly chosen display assumptions. This constructor does not accept them for the user.
    public init(profileID: String = "simunow.preview.genericCone", profileVersion: Int = 1,
                baseRadiusMeters: Double = 0.05, halfAngleDegrees: Double = 12, lengthMeters: Double? = nil,
                pathCount: Int = 32, maximumSegments: Int = 128, seed: UInt32 = 1,
                minimumStrength: Double = 0.01, source: SourceRecord = .init(kind: .assumed, note: "Internal geometric display assumption, not measured airflow.")) {
        self.profileID = profileID; self.profileVersion = profileVersion; self.baseRadiusMeters = baseRadiusMeters
        self.halfAngleDegrees = halfAngleDegrees; self.lengthMeters = lengthMeters; self.pathCount = pathCount
        self.maximumSegments = maximumSegments; self.seed = seed; self.minimumStrength = minimumStrength; self.source = source
    }
}
public enum AnalysisTimeBasis: String, Codable, Sendable { case fixed24HourReference }
public struct AnalysisTimeWindow: Codable, Equatable, Sendable {
    public let startMinute: Int
    public let endMinute: Int
    public init(startMinute: Int, endMinute: Int) { self.startMinute = startMinute; self.endMinute = endMinute }
}
public enum ElectricalPowerBasis: String, Codable, CaseIterable, Sendable {
    case measuredAverage, declaredScenario, ratedContinuous
}
public struct AnalysisPowerInterval: Codable, Equatable, Sendable {
    public let startMinute: Int
    public let endMinute: Int
    public let power: ElectricalPower
    public let basis: ElectricalPowerBasis
    public init(startMinute: Int, endMinute: Int, power: ElectricalPower, basis: ElectricalPowerBasis) {
        self.startMinute = startMinute; self.endMinute = endMinute; self.power = power; self.basis = basis
    }
}
public struct PowerEstimateConfiguration: Codable, Equatable, Sendable {
    public let timeBasis: AnalysisTimeBasis
    public let requestedWindows: [AnalysisTimeWindow]
    public let intervals: [AnalysisPowerInterval]
    public init(timeBasis: AnalysisTimeBasis = .fixed24HourReference,
                requestedWindows: [AnalysisTimeWindow], intervals: [AnalysisPowerInterval]) {
        self.timeBasis = timeBasis; self.requestedWindows = requestedWindows; self.intervals = intervals
    }
}
public enum HeatConductanceTag: QuantityTag { public static let unit = "W/K" }
public enum SpecificHeatTag: QuantityTag { public static let unit = "J/(kg.K)" }
public typealias HeatConductance = PhysicalParameter<HeatConductanceTag>
public typealias SpecificHeat = PhysicalParameter<SpecificHeatTag>
public struct SteadyHeatBalanceConfiguration: Codable, Equatable, Sendable {
    public let conditionMinute: Int
    public let conductance: HeatConductance
    public let indoorTemperature: Temperature
    public let outdoorTemperature: Temperature
    public let outdoorAir: VolumeFlow
    public let infiltration: VolumeFlow
    public let density: Density
    public let specificHeat: SpecificHeat
    public let internalSensibleHeat: ThermalPower
    public let solarSensibleHeat: ThermalPower
    public let excludedTerms: [String]
    public let sensibleCoolingCapacity: ThermalPower?
    public init(conditionMinute: Int, conductance: HeatConductance, indoorTemperature: Temperature,
                outdoorTemperature: Temperature, outdoorAir: VolumeFlow, infiltration: VolumeFlow,
                density: Density, specificHeat: SpecificHeat, internalSensibleHeat: ThermalPower,
                solarSensibleHeat: ThermalPower, excludedTerms: [String] = [], sensibleCoolingCapacity: ThermalPower? = nil) {
        self.conditionMinute = conditionMinute; self.conductance = conductance; self.indoorTemperature = indoorTemperature
        self.outdoorTemperature = outdoorTemperature; self.outdoorAir = outdoorAir; self.infiltration = infiltration
        self.density = density; self.specificHeat = specificHeat; self.internalSensibleHeat = internalSensibleHeat
        self.solarSensibleHeat = solarSensibleHeat; self.excludedTerms = excludedTerms; self.sensibleCoolingCapacity = sensibleCoolingCapacity
    }
}
public enum AnalysisConfigurationPayload: Equatable, Sendable, Codable {
    case airflowPreview(AirflowPreviewConfiguration)
    case powerEstimate(PowerEstimateConfiguration)
    case steadyHeatBalance(SteadyHeatBalanceConfiguration)
    public var kind: AnalysisKind {
        switch self { case .airflowPreview: .airflowPreview; case .powerEstimate: .powerEstimate; case .steadyHeatBalance: .steadyHeatBalance }
    }
    enum Keys: String, CodingKey { case kind, value }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(AnalysisKind.self, forKey: .kind) {
        case .airflowPreview: self = .airflowPreview(try c.decode(AirflowPreviewConfiguration.self, forKey: .value))
        case .powerEstimate: self = .powerEstimate(try c.decode(PowerEstimateConfiguration.self, forKey: .value))
        case .steadyHeatBalance: self = .steadyHeatBalance(try c.decode(SteadyHeatBalanceConfiguration.self, forKey: .value))
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self); try c.encode(kind, forKey: .kind)
        switch self {
        case .airflowPreview(let v): try c.encode(v, forKey: .value)
        case .powerEstimate(let v): try c.encode(v, forKey: .value)
        case .steadyHeatBalance(let v): try c.encode(v, forKey: .value)
        }
    }
}
public struct AnalysisConfiguration: Codable, Equatable, Sendable {
    public let configVersion: Int
    public let roomID: UUID?
    public let deviceID: UUID?
    public let payload: AnalysisConfigurationPayload
    public let acceptedAssumptions: [AnalysisAssumption]
    public let resources: AnalysisResourceLimits
    public init(configVersion: Int = 1, roomID: UUID? = nil, deviceID: UUID? = nil,
                payload: AnalysisConfigurationPayload, acceptedAssumptions: [AnalysisAssumption] = [],
                resources: AnalysisResourceLimits = .standard) {
        self.configVersion = configVersion; self.roomID = roomID; self.deviceID = deviceID
        self.payload = payload; self.acceptedAssumptions = acceptedAssumptions; self.resources = resources
    }
}
public struct ScenarioAnalysisConfiguration: Codable, Equatable, Sendable {
    public let scenarioID: UUID
    public let configuration: AnalysisConfiguration
    public init(scenarioID: UUID, configuration: AnalysisConfiguration) { self.scenarioID = scenarioID; self.configuration = configuration }
}
public struct AnalysisConfigurationStore: Codable, Equatable, Sendable {
    public let storeVersion: Int
    public let projectID: UUID
    public var entries: [ScenarioAnalysisConfiguration]
    public init(storeVersion: Int = 1, projectID: UUID, entries: [ScenarioAnalysisConfiguration] = []) {
        self.storeVersion = storeVersion; self.projectID = projectID; self.entries = entries
    }
    public func configuration(scenarioID: UUID, kind: AnalysisKind) -> AnalysisConfiguration? {
        entries.first { $0.scenarioID == scenarioID && $0.configuration.payload.kind == kind }?.configuration
    }
    public mutating func set(_ configuration: AnalysisConfiguration, scenarioID: UUID) {
        entries.removeAll { $0.scenarioID == scenarioID && $0.configuration.payload.kind == configuration.payload.kind }
        entries.append(.init(scenarioID: scenarioID, configuration: configuration))
    }
}
