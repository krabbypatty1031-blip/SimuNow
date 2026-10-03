import Foundation

public enum NativeAnalysisRecord: String, Sendable {
    case request = "local-analysis-request"
    case event = "local-analysis-event"
    case result = "local-analysis-result"
    case manifest = "analysis-artifact-manifest"
    case configuration = "analysis-configuration"
    case costEvaluation = "cost-evaluation"
    case comparisonSnapshot = "comparison-snapshot"
    case comparisonRecord = "comparison-record"
    case measurementDataset = "measurement-dataset"
    case professionalReviewConfiguration = "professional-review-configuration"
    case professionalReviewReceipt = "professional-review-receipt"
    case roomCapture = "room-capture"
    case redactedReport = "redacted-report"
    case redactedMeasurements = "redacted-measurements"
    case jetCalibration = "jet-calibration"
}
/// A separate strict wire boundary; it never changes project v2 or P0 quality semantics.
public struct NativeAnalysisCodec: Sendable {
    public let registry: ModelRegistry
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    // Per-record immutable lazy resources: opening a configuration does not parse
    // all unrelated report, measurement and research schemas on the UI thread.
    private enum SchemaResources {
        private static func load(_ record: NativeAnalysisRecord) -> Result<JSONValue, ProjectDataError> {
            do {
                guard let url = Bundle.module.url(forResource: record.rawValue + ".schema", withExtension: "json")
                else { throw ProjectDataError.contract("Missing native schema resource") }
                return .success(try JSONValue(data: Data(contentsOf: url)))
            } catch { return .failure(.contract("Native schema load: \(error)")) }
        }
        static let request = load(.request)
        static let event = load(.event)
        static let result = load(.result)
        static let manifest = load(.manifest)
        static let configuration = load(.configuration)
        static let costEvaluation = load(.costEvaluation)
        static let comparisonSnapshot = load(.comparisonSnapshot)
        static let comparisonRecord = load(.comparisonRecord)
        static let measurementDataset = load(.measurementDataset)
        static let jetCalibration = load(.jetCalibration)
        static let professionalReviewConfiguration = load(.professionalReviewConfiguration)
        static let professionalReviewReceipt = load(.professionalReviewReceipt)
        static let redactedReport = load(.redactedReport)
        static let redactedMeasurements = load(.redactedMeasurements)
        static let roomCapture = load(.roomCapture)
    }
    public static func schema(_ record: NativeAnalysisRecord) throws -> JSONValue {
        let value: Result<JSONValue, ProjectDataError>
        switch record {
        case .request: value = SchemaResources.request
        case .event: value = SchemaResources.event
        case .result: value = SchemaResources.result
        case .manifest: value = SchemaResources.manifest
        case .configuration: value = SchemaResources.configuration
        case .costEvaluation: value = SchemaResources.costEvaluation
        case .comparisonSnapshot: value = SchemaResources.comparisonSnapshot
        case .comparisonRecord: value = SchemaResources.comparisonRecord
        case .measurementDataset: value = SchemaResources.measurementDataset
        case .jetCalibration: value = SchemaResources.jetCalibration
        case .professionalReviewConfiguration: value = SchemaResources.professionalReviewConfiguration
        case .professionalReviewReceipt: value = SchemaResources.professionalReviewReceipt
        case .redactedReport: value = SchemaResources.redactedReport
        case .redactedMeasurements: value = SchemaResources.redactedMeasurements
        case .roomCapture: value = SchemaResources.roomCapture
        }
        return try value.get()
    }
    public func encodeRequest(_ value: LocalAnalysisRequest) throws -> Data {
        try encode(value, record: .request, validate: validateRequest)
    }
    public func decodeRequest(_ data: Data) throws -> LocalAnalysisRequest {
        try decode(data, record: .request, validate: validateRequest)
    }
    public func encodeResult(_ value: LocalAnalysisResult) throws -> Data {
        try encode(value, record: .result, validate: validateResult)
    }
    public func decodeResult(_ data: Data) throws -> LocalAnalysisResult {
        try decode(data, record: .result, validate: validateResult)
    }
    public func encodeEvent(_ value: LocalAnalysisEvent) throws -> Data {
        try encode(value, record: .event, validate: validateEvent)
    }
    public func decodeEvent(_ data: Data) throws -> LocalAnalysisEvent {
        try decode(data, record: .event, validate: validateEvent)
    }
    public func encodeManifest(_ value: AnalysisArtifactManifest) throws -> Data {
        try encode(value, record: .manifest, validate: validateManifest)
    }
    public func decodeManifest(_ data: Data) throws -> AnalysisArtifactManifest {
        try decode(data, record: .manifest, validate: validateManifest)
    }
    public func encodeConfiguration(_ value: AnalysisConfigurationStore) throws -> Data {
        try encode(value, record: .configuration, validate: validateStore)
    }
    public func decodeConfiguration(_ data: Data) throws -> AnalysisConfigurationStore {
        try decode(data, record: .configuration, validate: validateStore)
    }
    public func encodeCostEvaluation(_ value: CostEvaluationRecord) throws -> Data {
        try encode(value, record: .costEvaluation, validate: validateCostEvaluation)
    }
    public func decodeCostEvaluation(_ data: Data) throws -> CostEvaluationRecord {
        try decode(data, record: .costEvaluation, validate: validateCostEvaluation)
    }
    public func encodeComparisonSnapshot(_ value: ComparisonSnapshot) throws -> Data {
        try encode(value, record: .comparisonSnapshot, validate: validateComparisonSnapshot)
    }
    public func decodeComparisonSnapshot(_ data: Data) throws -> ComparisonSnapshot {
        try decode(data, record: .comparisonSnapshot, validate: validateComparisonSnapshot)
    }
    public func encodeComparisonRecord(_ value: ComparisonRecord) throws -> Data {
        try encode(value, record: .comparisonRecord, validate: validateComparisonRecord)
    }
    public func decodeComparisonRecord(_ data: Data) throws -> ComparisonRecord {
        try decode(data, record: .comparisonRecord, validate: validateComparisonRecord)
    }
    public func validateComparisonRecord(_ value: ComparisonRecord) throws {
        try validateComparisonSnapshot(value.snapshot)
        guard value.references.map(\.run) == value.snapshot.runs,
              Set(value.snapshot.runs.map(\.runID)).count == value.snapshot.runs.count,
              Set(value.snapshot.runs.map(\.scenarioID)).count == value.snapshot.runs.count else {
            throw ProjectDataError.contract("固定比较的引用重复或不一致。")
        }
    }
    public func validateCostEvaluation(_ value: CostEvaluationRecord) throws {
        try ThermalEstimateValidation.validateWindows(value.configuration.requestedWindows)
        try ThermalEstimateValidation.validateWindows(value.configuration.tariffs.map { .init(startMinute:$0.startMinute,endMinute:$0.endMinute) },requireNonempty:false)
        for t in value.configuration.tariffs {
            try ThermalEstimateValidation.validateParameter(t.rate)
            if case .known(let rate,_,let bounds) = t.rate {
                try ThermalEstimateValidation.validateCostNumericInput(rate)
                if let bounds { try ThermalEstimateValidation.validateCostNumericInput(bounds.lower); try ThermalEstimateValidation.validateCostNumericInput(bounds.upper) }
            }
        }
        guard value.payload.missingReasons.isEmpty == (value.payload.totalCostDecimal != nil),
              value.payload.totalCostDecimal == nil || value.configuration.currency?.range(of:"^[A-Z]{3}$",options:.regularExpression) != nil else { throw ProjectDataError.contract("Cost completeness/currency mismatch") }
        for segment in value.payload.segments { guard segment.startMinute < segment.endMinute else { throw ProjectDataError.contract("Invalid cost segment") } }
    }
    public func validateComparisonSnapshot(_ value: ComparisonSnapshot) throws {
        let metrics = value.metrics ?? []
        guard metrics.count <= 16, Set(metrics.map(\.metric)).count == metrics.count else { throw ProjectDataError.contract("Invalid comparison metrics") }
        for m in metrics {
            guard [m.baseline,m.candidate,m.absoluteDifference,m.percentDifference].compactMap({$0}).allSatisfy(\.isFinite),
                  m.reasons.isEmpty || m.percentDifference == nil, m.baseline != 0 || m.percentDifference == nil else { throw ProjectDataError.contract("Undefined comparison percentage") }
        }
    }
    public func validateRequestWire(_ value: LocalAnalysisRequest) throws {
        _ = try validatedTree(value, record: .request, validate: validateRequest)
    }
    private func validatedTree<T: Encodable>(
        _ v: T, record: NativeAnalysisRecord,
        validate: (T) throws -> Void
    ) throws -> JSONValue {
        let tree = try JSONTreeCoding.encode(v)
        try WireSchema.validate(tree, schema: Self.schema(record))
        try validate(v)
        return tree
    }
    private func encode<T: Encodable>(_ v: T, record: NativeAnalysisRecord, validate: (T) throws -> Void)
        throws -> Data
    {
        try validatedTree(v, record: record, validate: validate).data()
    }
    private func decode<T: Decodable>(
        _ data: Data, record: NativeAnalysisRecord, validate: (T) throws -> Void
    ) throws -> T {
        let tree = try JSONValue(data: data)
        try WireSchema.validate(tree, schema: Self.schema(record))
        let v = try JSONTreeCoding.decode(T.self, from: tree)
        try validate(v)
        return v
    }
    public func validateRequest(_ request: LocalAnalysisRequest) throws {
        guard request.identity.scenarioID == request.resolvedInput.snapshot.scenarioID,
            request.method.kind == request.resolvedInput.configuration.payload.kind,
            request.limits == request.resolvedInput.configuration.resources
        else { throw ProjectDataError.contract("Native request identity/configuration mismatch") }
        try ProjectCodec(registry: registry).validateSnapshot(request.resolvedInput.snapshot)
        try validateConfiguration(request.resolvedInput.configuration)
        guard
            request.resolvedInput.adoptedAssumptions
                == request.resolvedInput.configuration.acceptedAssumptions
        else { throw ProjectDataError.contract("Unaccepted assumptions") }
    }
    public func validateConfiguration(_ config: AnalysisConfiguration) throws {
        let limits = config.resources
        guard (1...64).contains(limits.maximumPaths), (1...128).contains(limits.maximumSegments),
            (0...128).contains(limits.maximumObstacles), (0...512).contains(limits.maximumTargets)
        else { throw ProjectDataError.contract("Invalid native resource limits") }
        guard config.configVersion == 1 else {
            throw ProjectDataError.unsupportedVersion(config.configVersion)
        }
        guard Set(config.acceptedAssumptions.map(\.id)).count == config.acceptedAssumptions.count else {
            throw ProjectDataError.contract("Duplicate assumptions")
        }
        for a in config.acceptedAssumptions {
            guard !a.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !a.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, a.version > 0
            else { throw ProjectDataError.contract("Invalid assumption") }
        }
        func windows(_ values: [(Int, Int)]) throws {
            var lastEnd = -1
            for (start, end) in values {
                guard 0 <= start, start < end, end <= 1440, start >= lastEnd else {
                    throw ProjectDataError.contract("Invalid or overlapping time intervals")
                }
                lastEnd = end
            }
        }
        switch config.payload {
        case .airflowPreview(let p):
            guard p.baseRadiusMeters.isFinite, p.baseRadiusMeters > 0, (1...45).contains(p.halfAngleDegrees),
                p.lengthMeters.map({ $0.isFinite && $0 > 0 }) ?? true,
                p.pathCount >= 1, p.maximumSegments >= 1, p.minimumStrength.isFinite,
                (0...1).contains(p.minimumStrength),
                p.pathCount <= config.resources.maximumPaths,
                p.maximumSegments <= config.resources.maximumSegments
            else { throw ProjectDataError.contract("Invalid preview profile/resources") }
        case .powerEstimate(let p):
            try windows(p.requestedWindows.map { ($0.startMinute, $0.endMinute) })
            try windows(p.intervals.map { ($0.startMinute, $0.endMinute) })
            try ThermalEstimateValidation.validatePower(p)
        case .steadyHeatBalance(let p): try ThermalEstimateValidation.validateHeat(p)
        }
        try validateParameters(try JSONTreeCoding.encode(config))
    }
    private func validateParameters(_ node: JSONValue) throws {
        if node["state"]?.string == "unknown" {
            guard let reason = node["reason"]?.string,
                !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ProjectDataError.contract("Missing unknown reason") }
        }
        if node["state"]?.string == "known" {
            guard let value = node["value"]?.double, value.isFinite else {
                throw ProjectDataError.contract("Nonfinite parameter")
            }
            let kind = node["source"]?["kind"]?.string
            if ["measured", "manufacturer", "preset"].contains(kind ?? ""),
                node["source"]?["reference"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    != false
            {
                throw ProjectDataError.contract("Missing parameter source reference")
            }
            if kind == "assumed",
                node["source"]?["note"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    != false
            {
                throw ProjectDataError.contract("Missing parameter assumption note")
            }
            let unit = node["unit"]?.string
            guard unit == "degC" ? value >= -273.15 : value >= 0 else {
                throw ProjectDataError.contract("Invalid parameter range")
            }
            if let bounds = node["uncertainty"], bounds != .null {
                guard let lower = bounds["lower"]?.double, let upper = bounds["upper"]?.double,
                    lower.isFinite, upper.isFinite, lower <= value, value <= upper,
                    bounds["meaning"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        == false
                else { throw ProjectDataError.contract("Invalid uncertainty bounds") }
            }
        }
        if let fields = node.fields { for v in fields.values { try validateParameters(v) } }
        if let items = node.items { for v in items { try validateParameters(v) } }
    }
    public func validateResult(_ result: LocalAnalysisResult) throws {
        guard result.method.kind == result.payload.kind, result.basis == result.method.resultBasis,
            result.elapsedSeconds.isFinite, result.elapsedSeconds >= 0
        else { throw ProjectDataError.contract("Native result method/basis mismatch") }
        for m in result.missingReasons {
            guard !m.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProjectDataError.contract("Missing result reason")
            }
        }
        if case .airflowPreview(let p) = result.payload {
            guard Set(p.paths.map(\.id)).count == p.paths.count, p.validEmissionCount >= 0 else {
                throw ProjectDataError.contract("Invalid preview path identity")
            }
            if let tolerance = p.geometryToleranceMeters {
                guard tolerance.isFinite, tolerance > 0, tolerance <= 1e-8 else {
                    throw ProjectDataError.contract("Invalid preview geometry tolerance")
                }
            }
            if let offset = p.wallSourceOffsetMeters {
                guard offset.isFinite, (0...1e-4).contains(offset) else {
                    throw ProjectDataError.contract("Invalid preview wall source offset")
                }
            }
            if let rejected = p.emissionRejections {
                guard rejected.count <= 64, Set(rejected.map(\.pathID)).count == rejected.count,
                    Set(rejected.map(\.pathID)).isDisjoint(with: Set(p.paths.map(\.id))),
                    rejected.allSatisfy({
                        (0...63).contains($0.pathID)
                            && ["emission_in_obstacle", "emission_outside_domain"].contains($0.reason)
                    })
                else { throw ProjectDataError.contract("Invalid preview emission rejection evidence") }
            }
            for r in p.relations {
                guard (r.state == .notEvaluated) == (r.missingReason != nil),
                    r.state != .occluded || r.hitEntityID != nil
                else { throw ProjectDataError.contract("Preview relation missing evidence") }
                guard r.hitPosition == nil || r.state == .occluded else {
                    throw ProjectDataError.contract("Hit position without occlusion")
                }
            }
        }
        func close(_ a:Double,_ b:Double)->Bool { a.isFinite && b.isFinite && abs(a-b)<=max(1e-9,max(abs(a),abs(b))*1e-9) }
        func envelope(_ nominal:Double?,_ lower:Double?,_ upper:Double?) throws {
            guard (lower == nil) == (upper == nil) else { throw ProjectDataError.contract("Incomplete result range") }
            if let lo=lower,let hi=upper { guard let nominal,lo.isFinite,hi.isFinite,lo>=0,lo<=nominal,nominal<=hi else { throw ProjectDataError.contract("Invalid result nominal/envelope") } }
        }
        if case .powerEstimate(let p)=result.payload {
            try ThermalEstimateValidation.validateWindows(p.requestedWindows,requireNonempty:result.checks.state == .passed)
            try ThermalEstimateValidation.validateWindows(p.segments.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute)},requireNonempty:false)
            var sum=0.0
            for s in p.segments {
                guard s.powerWatts.isFinite,s.powerWatts>=0,s.energyKWh>=0,close(s.energyKWh,s.powerWatts*Double(s.endMinute-s.startMinute)/60000),
                      p.requestedWindows.contains(where:{$0.startMinute<=s.startMinute && $0.endMinute>=s.endMinute}) else { throw ProjectDataError.contract("Invalid power result segment") }
                sum += s.energyKWh
            }
            guard close(p.knownSubtotalKWh,sum) else { throw ProjectDataError.contract("Power subtotal differs from segments") }
            if let total=p.totalEnergyKWh { guard close(total,sum) else { throw ProjectDataError.contract("Power total differs from segments") } }
            if result.checks.state == .passed {
                guard let total=p.totalEnergyKWh,close(total,sum),result.missingReasons.isEmpty else { throw ProjectDataError.contract("Passed power result has missing complete total") }
                for w in p.requestedWindows {
                    var cursor=w.startMinute
                    for s in p.segments where s.startMinute>=w.startMinute && s.endMinute<=w.endMinute {
                        guard s.startMinute==cursor else { throw ProjectDataError.contract("Passed power result has coverage gap") };cursor=s.endMinute
                    }
                    guard cursor==w.endMinute else { throw ProjectDataError.contract("Passed power result is partial") }
                }
            }
            try envelope(p.totalEnergyKWh,p.lowerEnergyKWh,p.upperEnergyKWh)
        }
        if case .steadyHeatBalance(let p)=result.payload {
            guard Set(p.excludedTerms).count == p.excludedTerms.count, Set(p.excludedTerms).isSubset(of:Set(ThermalEstimateValidation.heatTerms)) else { throw ProjectDataError.contract("Unknown or duplicate excluded result term") }
            guard Set(p.terms.map(\.id)).count==p.terms.count,p.terms.allSatisfy({$0.signedWatts.isFinite && ThermalEstimateValidation.heatTerms.contains($0.id)}) else { throw ProjectDataError.contract("Invalid or repeated heat ledger term") }
            if result.checks.state == .passed {
                guard let total=p.totalSignedWatts,let cooling=p.coolingSensibleWatts,close(total,p.terms.reduce(0){$0+$1.signedWatts}),close(cooling,max(0,total)),result.missingReasons.isEmpty,
                      p.completeness == (p.excludedTerms.isEmpty ? .completeDeclaredCase:.declaredSubset),
                      Set(p.terms.map(\.id)) == Set(ThermalEstimateValidation.heatTerms).subtracting(p.excludedTerms),
                      p.excludedTerms.isEmpty || p.capacityScreen == .cannotEvaluate else { throw ProjectDataError.contract("Passed heat ledger incomplete or mislabeled") }
            }
            try envelope(p.coolingSensibleWatts,p.lowerCoolingSensibleWatts,p.upperCoolingSensibleWatts)
            if let scenarios=p.scenarios {
                guard !scenarios.isEmpty,scenarios.count<=5,Set(scenarios.map(\.id)).count==scenarios.count,let nominal=scenarios.first(where:{$0.id=="nominal"}),close(nominal.totalSignedWatts,p.totalSignedWatts ?? .nan),close(nominal.coolingSensibleWatts,p.coolingSensibleWatts ?? .nan),scenarios.allSatisfy({close($0.coolingSensibleWatts,max(0,$0.totalSignedWatts))}),close(scenarios.map(\.coolingSensibleWatts).min()!,p.lowerCoolingSensibleWatts ?? .nan),close(scenarios.map(\.coolingSensibleWatts).max()!,p.upperCoolingSensibleWatts ?? .nan) else { throw ProjectDataError.contract("Heat scenarios/envelope mismatch") }
            }
        }
        guard !result.provenance.cacheHit || result.provenance.sourceRunID != nil else {
            throw ProjectDataError.contract("Cache hit missing source identity")
        }
    }
    public func validateEvent(_ event: LocalAnalysisEvent) throws {
        guard (event.stage == .completed) == (event.result != nil),
            (event.stage == .failed) == (event.failure != nil),
            (event.stage == .progress) == (event.progress != nil)
        else { throw ProjectDataError.contract("Event stage/payload mismatch") }
        if let p = event.progress {
            guard p.isFinite, (0...1).contains(p) else { throw ProjectDataError.contract("Invalid progress") }
        }
        if let result = event.result {
            guard result.identity.runID == event.runID, result.identity.scenarioID == event.scenarioID else {
                throw ProjectDataError.contract("Event identity mismatch")
            }
            try validateResult(result)
        }
    }
    public func validateManifest(_ value: AnalysisArtifactManifest) throws {
        guard Set(value.files.map(\.relativePath)).count == value.files.count,
            Set(value.files.map(\.relativePath)).isSuperset(of: ["input.json", "result.json"])
        else { throw ProjectDataError.contract("Missing/duplicate artifact files") }
    }
    public func validateStore(_ value: AnalysisConfigurationStore) throws {
        let keys = value.entries.map {
            $0.scenarioID.uuidString + "|" + $0.configuration.payload.kind.rawValue
        }
        guard Set(keys).count == keys.count else {
            throw ProjectDataError.contract("Duplicate scenario/method configuration")
        }
        for e in value.entries { try validateConfiguration(e.configuration) }
    }
}
