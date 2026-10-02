import Foundation

public enum NativeAnalysisRecord: String, Sendable {
    case request = "local-analysis-request", event = "local-analysis-event", result = "local-analysis-result"
    case manifest = "analysis-artifact-manifest", configuration = "analysis-configuration"
}
/// A separate strict wire boundary; it never changes project v2 or P0 quality semantics.
public struct NativeAnalysisCodec: Sendable {
    public let registry: ModelRegistry
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    private static let schemas: [String: Result<JSONValue, ProjectDataError>] = {
        var values: [String: Result<JSONValue, ProjectDataError>] = [:]
        for record in [NativeAnalysisRecord.request, .event, .result, .manifest, .configuration] {
            do {
                guard let url = Bundle.module.url(forResource: record.rawValue+".schema", withExtension: "json") else { throw ProjectDataError.contract("Missing native schema resource") }
                values[record.rawValue] = .success(try JSONValue(data: Data(contentsOf: url)))
            } catch { values[record.rawValue] = .failure(.contract("Native schema load: \(error)")) }
        }
        return values
    }()
    public static func schema(_ record: NativeAnalysisRecord) throws -> JSONValue {
        guard let schema = schemas[record.rawValue] else { throw ProjectDataError.contract("Missing native schema resource") }; return try schema.get()
    }
    public func encodeRequest(_ value: LocalAnalysisRequest) throws -> Data { try encode(value, record: .request, validate: validateRequest) }
    public func decodeRequest(_ data: Data) throws -> LocalAnalysisRequest { try decode(data, record: .request, validate: validateRequest) }
    public func encodeResult(_ value: LocalAnalysisResult) throws -> Data { try encode(value, record: .result, validate: validateResult) }
    public func decodeResult(_ data: Data) throws -> LocalAnalysisResult { try decode(data, record: .result, validate: validateResult) }
    public func encodeEvent(_ value: LocalAnalysisEvent) throws -> Data { try encode(value, record: .event, validate: validateEvent) }
    public func decodeEvent(_ data: Data) throws -> LocalAnalysisEvent { try decode(data, record: .event, validate: validateEvent) }
    public func encodeManifest(_ value: AnalysisArtifactManifest) throws -> Data { try encode(value, record: .manifest, validate: validateManifest) }
    public func decodeManifest(_ data: Data) throws -> AnalysisArtifactManifest { try decode(data, record: .manifest, validate: validateManifest) }
    public func encodeConfiguration(_ value: AnalysisConfigurationStore) throws -> Data { try encode(value, record: .configuration, validate: validateStore) }
    public func decodeConfiguration(_ data: Data) throws -> AnalysisConfigurationStore { try decode(data, record: .configuration, validate: validateStore) }
    private func encode<T: Encodable>(_ v: T, record: NativeAnalysisRecord, validate: (T) throws -> Void) throws -> Data {
        let tree = try JSONTreeCoding.encode(v); try WireSchema.validate(tree, schema: Self.schema(record)); try validate(v); return try tree.data()
    }
    private func decode<T: Decodable>(_ data: Data, record: NativeAnalysisRecord, validate: (T) throws -> Void) throws -> T {
        let tree = try JSONValue(data: data); try WireSchema.validate(tree, schema: Self.schema(record))
        let v = try JSONTreeCoding.decode(T.self, from: tree); try validate(v); return v
    }
    public func validateRequest(_ request: LocalAnalysisRequest) throws {
        guard request.identity.scenarioID == request.resolvedInput.snapshot.scenarioID,
              request.method.kind == request.resolvedInput.configuration.payload.kind,
              request.limits == request.resolvedInput.configuration.resources else { throw ProjectDataError.contract("Native request identity/configuration mismatch") }
        _ = try ProjectCodec(registry: registry).encodeSnapshot(request.resolvedInput.snapshot)
        try validateConfiguration(request.resolvedInput.configuration)
        guard request.resolvedInput.adoptedAssumptions == request.resolvedInput.configuration.acceptedAssumptions else { throw ProjectDataError.contract("Unaccepted assumptions") }
    }
    public func validateConfiguration(_ config: AnalysisConfiguration) throws {
        let limits = config.resources
        guard (1...64).contains(limits.maximumPaths), (1...128).contains(limits.maximumSegments),
              (0...128).contains(limits.maximumObstacles), (0...512).contains(limits.maximumTargets) else { throw ProjectDataError.contract("Invalid native resource limits") }
        guard config.configVersion == 1 else { throw ProjectDataError.unsupportedVersion(config.configVersion) }
        guard Set(config.acceptedAssumptions.map(\.id)).count == config.acceptedAssumptions.count else { throw ProjectDataError.contract("Duplicate assumptions") }
        for a in config.acceptedAssumptions {
            guard !a.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !a.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, a.version > 0 else { throw ProjectDataError.contract("Invalid assumption") }
        }
        func windows(_ values: [(Int,Int)]) throws {
            var lastEnd = -1
            for (start,end) in values {
                guard 0 <= start, start < end, end <= 1440, start >= lastEnd else { throw ProjectDataError.contract("Invalid or overlapping time intervals") }
                lastEnd = end
            }
        }
        switch config.payload {
        case .airflowPreview(let p):
            guard p.baseRadiusMeters.isFinite, p.baseRadiusMeters > 0, (1...45).contains(p.halfAngleDegrees),
                  p.lengthMeters.map({ $0.isFinite && $0 > 0 }) ?? true,
                  p.pathCount >= 1, p.maximumSegments >= 1, p.minimumStrength.isFinite, (0...1).contains(p.minimumStrength),
                  p.pathCount <= config.resources.maximumPaths, p.maximumSegments <= config.resources.maximumSegments else { throw ProjectDataError.contract("Invalid preview profile/resources") }
        case .powerEstimate(let p):
            try windows(p.requestedWindows.map { ($0.startMinute,$0.endMinute) }); try windows(p.intervals.map { ($0.startMinute,$0.endMinute) })
        case .steadyHeatBalance: break
        }
        try validateParameters(try JSONTreeCoding.encode(config))
    }
    private func validateParameters(_ node: JSONValue) throws {
        if node["state"]?.string == "unknown" {
            guard let reason = node["reason"]?.string, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectDataError.contract("Missing unknown reason") }
        }
        if node["state"]?.string == "known" {
            guard let value = node["value"]?.double, value.isFinite else { throw ProjectDataError.contract("Nonfinite parameter") }
            let kind = node["source"]?["kind"]?.string
            if ["measured", "manufacturer", "preset"].contains(kind ?? ""), node["source"]?["reference"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { throw ProjectDataError.contract("Missing parameter source reference") }
            if kind == "assumed", node["source"]?["note"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { throw ProjectDataError.contract("Missing parameter assumption note") }
            let unit = node["unit"]?.string
            guard unit == "degC" ? value >= -273.15 : value >= 0 else { throw ProjectDataError.contract("Invalid parameter range") }
            if let bounds = node["uncertainty"], bounds != .null {
                guard let lower = bounds["lower"]?.double, let upper = bounds["upper"]?.double,
                      lower.isFinite, upper.isFinite, lower <= value, value <= upper,
                      bounds["meaning"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw ProjectDataError.contract("Invalid uncertainty bounds") }
            }
        }
        if let fields = node.fields { for v in fields.values { try validateParameters(v) } }
        if let items = node.items { for v in items { try validateParameters(v) } }
    }
    public func validateResult(_ result: LocalAnalysisResult) throws {
        guard result.method.kind == result.payload.kind, result.basis == result.method.resultBasis,
              result.elapsedSeconds.isFinite, result.elapsedSeconds >= 0 else { throw ProjectDataError.contract("Native result method/basis mismatch") }
        for m in result.missingReasons { guard !m.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectDataError.contract("Missing result reason") } }
        if case .airflowPreview(let p) = result.payload {
            guard Set(p.paths.map(\.id)).count == p.paths.count, p.validEmissionCount >= 0 else { throw ProjectDataError.contract("Invalid preview path identity") }
            for r in p.relations {
                guard (r.state == .notEvaluated) == (r.missingReason != nil), r.state != .occluded || r.hitEntityID != nil else { throw ProjectDataError.contract("Preview relation missing evidence") }
            }
        }
        guard !result.provenance.cacheHit || result.provenance.sourceRunID != nil else { throw ProjectDataError.contract("Cache hit missing source identity") }
    }
    public func validateEvent(_ event: LocalAnalysisEvent) throws {
        guard (event.stage == .completed) == (event.result != nil),
              (event.stage == .failed) == (event.failure != nil),
              (event.stage == .progress) == (event.progress != nil) else { throw ProjectDataError.contract("Event stage/payload mismatch") }
        if let p = event.progress { guard p.isFinite, (0...1).contains(p) else { throw ProjectDataError.contract("Invalid progress") } }
        if let result = event.result {
            guard result.identity.runID == event.runID, result.identity.scenarioID == event.scenarioID else { throw ProjectDataError.contract("Event identity mismatch") }
            try validateResult(result)
        }
    }
    public func validateManifest(_ value: AnalysisArtifactManifest) throws {
        guard Set(value.files.map(\.relativePath)).count == value.files.count,
              Set(value.files.map(\.relativePath)).isSuperset(of: ["input.json","result.json"]) else { throw ProjectDataError.contract("Missing/duplicate artifact files") }
    }
    public func validateStore(_ value: AnalysisConfigurationStore) throws {
        let keys = value.entries.map { $0.scenarioID.uuidString+"|"+$0.configuration.payload.kind.rawValue }
        guard Set(keys).count == keys.count else { throw ProjectDataError.contract("Duplicate scenario/method configuration") }
        for e in value.entries { try validateConfiguration(e.configuration) }
    }
}
