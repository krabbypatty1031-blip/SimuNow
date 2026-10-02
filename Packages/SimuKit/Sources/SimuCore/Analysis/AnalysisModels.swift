import Foundation

public enum AnalysisCapability: String, Codable, CaseIterable, Sendable { case roomView, airflowPreview, powerEstimate, steadyHeatBalance }
public enum AnalysisIssueSeverity: String, Codable, Sendable { case warning, blocker }
public struct AnalysisIssue: Codable, Equatable, Sendable {
    public let code: String
    public let severity: AnalysisIssueSeverity
    public let scope: AnalysisCapability
    public let entityID: UUID?
    public let fieldPath: String
    public let message: String
    public let repairAction: String?
    public init(code: String, severity: AnalysisIssueSeverity = .blocker, scope: AnalysisCapability,
                entityID: UUID? = nil, fieldPath: String, message: String, repairAction: String? = nil) {
        self.code = code; self.severity = severity; self.scope = scope; self.entityID = entityID
        self.fieldPath = fieldPath; self.message = message; self.repairAction = repairAction
    }
}
public struct AnalysisReadiness: Codable, Equatable, Sendable {
    public let capability: AnalysisCapability
    public let blockers: [AnalysisIssue]
    public let warnings: [AnalysisIssue]
    public let unsupportedEntities: [UUID]
    public var eligible: Bool { blockers.isEmpty }
    public init(capability: AnalysisCapability, blockers: [AnalysisIssue] = [], warnings: [AnalysisIssue] = [], unsupportedEntities: [UUID] = []) {
        self.capability = capability; self.blockers = blockers; self.warnings = warnings; self.unsupportedEntities = unsupportedEntities
    }
}
public struct ResolvedAnalysisInput: Codable, Equatable, Sendable {
    public let snapshot: ScenarioInputSnapshot
    public let configuration: AnalysisConfiguration
    public let adoptedAssumptions: [AnalysisAssumption]
    public init(snapshot: ScenarioInputSnapshot, configuration: AnalysisConfiguration, adoptedAssumptions: [AnalysisAssumption]) {
        self.snapshot = snapshot; self.configuration = configuration; self.adoptedAssumptions = adoptedAssumptions
    }
}
public struct LocalAnalysisRequest: Codable, Equatable, Sendable {
    public let requestVersion: Int
    public let identity: RunIdentity
    public let method: AnalysisMethod
    public let resolvedInput: ResolvedAnalysisInput
    public let snapshotHash: String
    public let computationHash: String
    public let hashFormat: String
    public let limits: AnalysisResourceLimits
    public init(requestVersion: Int = 1, identity: RunIdentity, method: AnalysisMethod, resolvedInput: ResolvedAnalysisInput,
                snapshotHash: String, computationHash: String, hashFormat: String = "simunow.native.canonical.v1", limits: AnalysisResourceLimits) {
        self.requestVersion = requestVersion; self.identity = identity; self.method = method; self.resolvedInput = resolvedInput
        self.snapshotHash = snapshotHash; self.computationHash = computationHash; self.hashFormat = hashFormat; self.limits = limits
    }
}
public struct AnalysisMissingReason: Codable, Equatable, Sendable {
    public let code: String
    public let fieldPath: String
    public let reason: String
    public init(code: String, fieldPath: String, reason: String) { self.code = code; self.fieldPath = fieldPath; self.reason = reason }
}
public enum AnalysisChecksState: String, Codable, Sendable { case passed, failed, notEvaluated }
public struct AnalysisChecks: Codable, Equatable, Sendable {
    public let state: AnalysisChecksState
    public let issues: [AnalysisIssue]
    public init(state: AnalysisChecksState, issues: [AnalysisIssue] = []) { self.state = state; self.issues = issues }
}
public enum PreviewPathTermination: String, Codable, Sendable { case hit, escaped, weak, lengthLimit, stepLimit }
public struct PreviewPathPoint: Codable, Equatable, Sendable {
    public let position: Position3D
    /// Dimensionless visual attenuation. Never a velocity.
    public let strength: Double
    public init(position: Position3D, strength: Double) { self.position = position; self.strength = strength }
}
public struct PreviewPath: Codable, Equatable, Sendable {
    public let id: Int
    public let points: [PreviewPathPoint]
    public let termination: PreviewPathTermination
    public let hitEntityID: UUID?
    public init(id: Int, points: [PreviewPathPoint], termination: PreviewPathTermination, hitEntityID: UUID? = nil) {
        self.id = id; self.points = points; self.termination = termination; self.hitEntityID = hitEntityID
    }
}
public enum PreviewRelationState: String, Codable, Sendable { case intersectsAssumedPath, occluded, outsideAssumedPath, notEvaluated }
public struct PreviewTargetRelation: Codable, Equatable, Sendable {
    public let seatID: UUID
    public let sampleID: UUID?
    public let position: Position3D
    public let isPositionMarker: Bool
    public let state: PreviewRelationState
    public let hitEntityID: UUID?
    public let missingReason: AnalysisMissingReason?
    public let ruleID: String
    public init(seatID: UUID, sampleID: UUID?, position: Position3D, isPositionMarker: Bool,
                state: PreviewRelationState, hitEntityID: UUID? = nil, missingReason: AnalysisMissingReason? = nil, ruleID: String) {
        self.seatID = seatID; self.sampleID = sampleID; self.position = position; self.isPositionMarker = isPositionMarker
        self.state = state; self.hitEntityID = hitEntityID; self.missingReason = missingReason; self.ruleID = ruleID
    }
}
public struct AirflowPreviewPayload: Codable, Equatable, Sendable {
    public let profileID: String
    public let profileVersion: Int
    public let strengthUnit: String
    public let paths: [PreviewPath]
    public let relations: [PreviewTargetRelation]
    public let validEmissionCount: Int
    public let excludedEntities: [UUID]
    public let notes: [String]
    public init(profileID: String, profileVersion: Int, paths: [PreviewPath], relations: [PreviewTargetRelation],
                validEmissionCount: Int, excludedEntities: [UUID] = [], notes: [String] = [], strengthUnit: String = "1") {
        self.profileID = profileID; self.profileVersion = profileVersion; self.strengthUnit = strengthUnit
        self.paths = paths; self.relations = relations; self.validEmissionCount = validEmissionCount
        self.excludedEntities = excludedEntities; self.notes = notes
    }
}
public struct PowerEstimateSegment: Codable, Equatable, Sendable {
    public let startMinute: Int
    public let endMinute: Int
    public let powerWatts: Double
    public let energyKWh: Double
    public let basis: ElectricalPowerBasis
    public init(startMinute: Int, endMinute: Int, powerWatts: Double, energyKWh: Double, basis: ElectricalPowerBasis) {
        self.startMinute = startMinute; self.endMinute = endMinute; self.powerWatts = powerWatts; self.energyKWh = energyKWh; self.basis = basis
    }
}
public struct PowerEstimatePayload: Codable, Equatable, Sendable {
    public let timeBasis: AnalysisTimeBasis
    public let requestedWindows: [AnalysisTimeWindow]
    public let segments: [PowerEstimateSegment]
    public let totalEnergyKWh: Double?
    public let knownSubtotalKWh: Double
    public let lowerEnergyKWh: Double?
    public let upperEnergyKWh: Double?
    public init(timeBasis: AnalysisTimeBasis = .fixed24HourReference, requestedWindows: [AnalysisTimeWindow],
                segments: [PowerEstimateSegment], totalEnergyKWh: Double?, knownSubtotalKWh: Double,
                lowerEnergyKWh: Double? = nil, upperEnergyKWh: Double? = nil) {
        self.timeBasis = timeBasis; self.requestedWindows = requestedWindows; self.segments = segments
        self.totalEnergyKWh = totalEnergyKWh; self.knownSubtotalKWh = knownSubtotalKWh
        self.lowerEnergyKWh = lowerEnergyKWh; self.upperEnergyKWh = upperEnergyKWh
    }
}
public struct HeatBalanceTerm: Codable, Equatable, Sendable {
    public let id: String
    public let signedWatts: Double
    public let description: String
    public init(id: String, signedWatts: Double, description: String) { self.id = id; self.signedWatts = signedWatts; self.description = description }
}
public enum SensibleCapacityScreen: String, Codable, Sendable { case sufficientForDeclaredSensibleCase, insufficientForDeclaredSensibleCase, cannotEvaluate }
public struct SteadyHeatBalancePayload: Codable, Equatable, Sendable {
    public let terms: [HeatBalanceTerm]
    public let totalSignedWatts: Double?
    public let coolingSensibleWatts: Double?
    public let excludedTerms: [String]
    public let capacityScreen: SensibleCapacityScreen
    public init(terms: [HeatBalanceTerm], totalSignedWatts: Double?, coolingSensibleWatts: Double?,
                excludedTerms: [String], capacityScreen: SensibleCapacityScreen = .cannotEvaluate) {
        self.terms = terms; self.totalSignedWatts = totalSignedWatts; self.coolingSensibleWatts = coolingSensibleWatts
        self.excludedTerms = excludedTerms; self.capacityScreen = capacityScreen
    }
}
public enum LocalAnalysisPayload: Codable, Equatable, Sendable {
    case airflowPreview(AirflowPreviewPayload), powerEstimate(PowerEstimatePayload), steadyHeatBalance(SteadyHeatBalancePayload)
    public var kind: AnalysisKind { switch self { case .airflowPreview: .airflowPreview; case .powerEstimate: .powerEstimate; case .steadyHeatBalance: .steadyHeatBalance } }
    enum Keys: String, CodingKey { case kind, value }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(AnalysisKind.self, forKey: .kind) {
        case .airflowPreview: self = .airflowPreview(try c.decode(AirflowPreviewPayload.self, forKey: .value))
        case .powerEstimate: self = .powerEstimate(try c.decode(PowerEstimatePayload.self, forKey: .value))
        case .steadyHeatBalance: self = .steadyHeatBalance(try c.decode(SteadyHeatBalancePayload.self, forKey: .value))
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self); try c.encode(kind, forKey: .kind)
        switch self { case .airflowPreview(let v): try c.encode(v, forKey: .value); case .powerEstimate(let v): try c.encode(v, forKey: .value); case .steadyHeatBalance(let v): try c.encode(v, forKey: .value) }
    }
}
public struct AnalysisCacheProvenance: Codable, Equatable, Sendable {
    public let cacheHit: Bool
    public let sourceRunID: UUID?
    public init(cacheHit: Bool = false, sourceRunID: UUID? = nil) { self.cacheHit = cacheHit; self.sourceRunID = sourceRunID }
}
public struct LocalAnalysisResult: Codable, Equatable, Sendable {
    public let resultVersion: Int
    public let identity: RunIdentity
    public let method: AnalysisMethod
    public let basis: AnalysisResultBasis
    public let checks: AnalysisChecks
    public let assumptions: [AnalysisAssumption]
    public let missingReasons: [AnalysisMissingReason]
    public let elapsedSeconds: Double
    public let payload: LocalAnalysisPayload
    public let provenance: AnalysisCacheProvenance
    public init(resultVersion: Int = 1, identity: RunIdentity, method: AnalysisMethod, checks: AnalysisChecks,
                assumptions: [AnalysisAssumption], missingReasons: [AnalysisMissingReason] = [], elapsedSeconds: Double,
                payload: LocalAnalysisPayload, provenance: AnalysisCacheProvenance = .init()) {
        self.resultVersion = resultVersion; self.identity = identity; self.method = method; self.basis = method.resultBasis
        self.checks = checks; self.assumptions = assumptions; self.missingReasons = missingReasons
        self.elapsedSeconds = elapsedSeconds; self.payload = payload; self.provenance = provenance
    }
}
public enum LocalAnalysisStage: String, Codable, Sendable {
    case accepted, validating, running, progress, checking, completed, failed, cancelled
    public var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}
public struct LocalAnalysisEvent: Codable, Equatable, Sendable {
    public let eventVersion: Int
    public let runID: UUID
    public let scenarioID: UUID
    public let sequence: Int
    public let stage: LocalAnalysisStage
    public let progress: Double?
    public let result: LocalAnalysisResult?
    public let failure: AnalysisMissingReason?
    public init(eventVersion: Int = 1, runID: UUID, scenarioID: UUID, sequence: Int, stage: LocalAnalysisStage,
                progress: Double? = nil, result: LocalAnalysisResult? = nil, failure: AnalysisMissingReason? = nil) {
        self.eventVersion = eventVersion; self.runID = runID; self.scenarioID = scenarioID; self.sequence = sequence
        self.stage = stage; self.progress = progress; self.result = result; self.failure = failure
    }
}
public struct AnalysisArtifactFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int
    public let sha256: String
    public init(relativePath: String, byteCount: Int, sha256: String) { self.relativePath = relativePath; self.byteCount = byteCount; self.sha256 = sha256 }
}
public struct AnalysisArtifactManifest: Codable, Equatable, Sendable {
    public let artifactVersion: Int
    public let owner: String
    public let runID: UUID
    public let scenarioID: UUID
    public let projectID: UUID
    public let requestVersion: Int
    public let resultVersion: Int
    public let files: [AnalysisArtifactFile]
    public init(artifactVersion: Int = 1, owner: String = "com.simunow.native-analysis", runID: UUID, scenarioID: UUID,
                projectID: UUID, requestVersion: Int = 1, resultVersion: Int = 1, files: [AnalysisArtifactFile]) {
        self.artifactVersion = artifactVersion; self.owner = owner; self.runID = runID; self.scenarioID = scenarioID
        self.projectID = projectID; self.requestVersion = requestVersion; self.resultVersion = resultVersion; self.files = files
    }
}
public enum AnalysisPersistenceState: Equatable, Sendable { case notSaved, saved, failed(String) }
