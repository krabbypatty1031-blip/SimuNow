import CryptoKit
import Foundation
import SimuCore

public struct AnalysisHashes: Equatable, Sendable {
    public let snapshotHash: String
    public let inputHash: String
    public let computationHash: String
}
public enum AnalysisResolutionError: Error, Equatable, Sendable {
    case notReady(AnalysisReadiness)
    case hashMismatch, unsupportedMethod
}
public struct AnalysisInputResolver: Sendable {
    public let registry: ModelRegistry
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    public func request(
        project: ProjectDocument, scenarioID: UUID, method: AnalysisMethod,
        configuration: AnalysisConfiguration, runID: UUID = UUID(), additionalIssues: [ValidationIssue] = []
    ) throws -> LocalAnalysisRequest {
        try prepare(
            project: project, scenarioID: scenarioID, method: method,
            configuration: configuration, runID: runID, additionalIssues: additionalIssues
        ).request
    }
    /// Reuses the exact readiness evaluated for this immutable request.
    public func prepare(
        project: ProjectDocument, scenarioID: UUID, method: AnalysisMethod,
        configuration: AnalysisConfiguration, runID: UUID = UUID(), additionalIssues: [ValidationIssue] = []
    )
        throws -> (request: LocalAnalysisRequest, readiness: AnalysisReadiness)
    {
        guard method.methodVersion == 1, method.kind == configuration.payload.kind else {
            throw AnalysisResolutionError.unsupportedMethod
        }
        let readiness = AnalysisReadinessEvaluator(registry: registry).evaluate(
            project: project, scenarioID: scenarioID,
            capability: AnalysisCapability(rawValue: method.kind.rawValue)!, configuration: configuration,
            additionalIssues: additionalIssues)
        guard readiness.eligible else { throw AnalysisResolutionError.notReady(readiness) }
        let input = ResolvedAnalysisInput(
            snapshot: try ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID),
            configuration: configuration, adoptedAssumptions: configuration.acceptedAssumptions)
        let hashes = try AnalysisHasher(registry: registry).hashes(input, method: method)
        let request = LocalAnalysisRequest(
            identity: .init(runID: runID, scenarioID: scenarioID, inputHash: hashes.inputHash),
            method: method, resolvedInput: input, snapshotHash: hashes.snapshotHash,
            computationHash: hashes.computationHash, limits: configuration.resources)
        try NativeAnalysisCodec(registry: registry).validateRequestWire(request)
        return (request, readiness)
    }
    public func validate(_ request: LocalAnalysisRequest) throws {
        try NativeAnalysisCodec(registry: registry).validateRequestWire(request)
        try validateHashesAndReadiness(request)
    }
    /// Public requests remain fully checked. Artifact creation reuses these exact
    /// validated wire bytes instead of performing a second encode/check pass.
    public func validatedRequestData(_ request: LocalAnalysisRequest) throws -> Data {
        let bytes = try NativeAnalysisCodec(registry: registry).encodeRequest(request)
        try validateHashesAndReadiness(request)
        return bytes
    }
    private func validateHashesAndReadiness(_ request: LocalAnalysisRequest) throws {
        let hashes = try AnalysisHasher(registry: registry).hashes(
            request.resolvedInput, method: request.method)
        guard request.hashFormat == AnalysisCanonicalizer.format, hashes.snapshotHash == request.snapshotHash,
            hashes.inputHash == request.identity.inputHash, hashes.computationHash == request.computationHash
        else { throw AnalysisResolutionError.hashMismatch }
        let snapshot = request.resolvedInput.snapshot
        let project = ProjectDocument(
            id: snapshot.projectID, name: "Run input", spaceType: .office, geometry: snapshot.geometry,
            scenarios: [
                .init(
                    id: snapshot.scenarioID, name: "Run input", inputs: snapshot.inputs,
                    evaluation: snapshot.evaluation)
            ])
        let readiness = AnalysisReadinessEvaluator(registry: registry).evaluate(
            project: project, scenarioID: snapshot.scenarioID,
            capability: AnalysisCapability(rawValue: request.method.kind.rawValue)!,
            configuration: request.resolvedInput.configuration)
        guard readiness.eligible else { throw AnalysisResolutionError.notReady(readiness) }
    }
}
public struct AnalysisHasher: Sendable {
    public let registry: ModelRegistry
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func hashes(_ input: ResolvedAnalysisInput, method: AnalysisMethod) throws -> AnalysisHashes {
        let root = try NativeAnalysisCodec.schema(.request)
        let snapshotTree = try JSONTreeCoding.encode(input.snapshot)
        let full = try AnalysisCanonicalizer.value(
            snapshotTree, schema: root["$defs"]?["ScenarioInputSnapshot"], root: root, registry: registry)
        let relevant = try projection(input, method: method, root: root)
        let inputHash = Self.sha256(
            try AnalysisCanonicalizer.bytes(
                .object(["format": .string(AnalysisCanonicalizer.format), "input": relevant])))
        let computation = NativeCanonicalValue.object([
            "format": .string(AnalysisCanonicalizer.format),
            "namespace": .string(
                "\(input.snapshot.projectID.uuidString.lowercased())/\(input.snapshot.scenarioID.uuidString.lowercased())/\(method.kind.rawValue)"
            ), "input": relevant,
        ])
        return .init(
            snapshotHash: Self.sha256(try AnalysisCanonicalizer.bytes(full)), inputHash: inputHash,
            computationHash: Self.sha256(try AnalysisCanonicalizer.bytes(computation)))
    }
    /// Fees are evaluations of an immutable power run, not a second numerical task.
    public func evaluationHash(
        identity: RunIdentity, evaluationConfiguration: JSONValue, evaluationVersion: Int = 1
    ) throws -> String {
        let body = NativeCanonicalValue.object([
            "runID": .string(identity.runID.uuidString.lowercased()),
            "inputHash": .string(identity.inputHash),
            "version": .integer(Int64(evaluationVersion)),
            "configuration": try AnalysisCanonicalizer.value(
                evaluationConfiguration, schema: nil, root: .object([:])),
        ])
        return Self.sha256(try AnalysisCanonicalizer.bytes(body))
    }
    private func projection(_ input: ResolvedAnalysisInput, method: AnalysisMethod, root: JSONValue) throws
        -> NativeCanonicalValue
    {
        func typed<T: Encodable>(_ v: T, _ definition: String) throws -> NativeCanonicalValue {
            try AnalysisCanonicalizer.value(
                JSONTreeCoding.encode(v), schema: root["$defs"]?[definition], root: root, registry: registry)
        }
        var fields: [String: NativeCanonicalValue] = [
            "projectID": .string(input.snapshot.projectID.uuidString.lowercased()),
            "scenarioID": .string(input.snapshot.scenarioID.uuidString.lowercased()),
            "method": try typed(method, "AnalysisMethod"),
            "configuration": try typed(input.configuration, "AnalysisConfiguration"),
            "assumptions": .array(try input.adoptedAssumptions.map { try typed($0, "AnalysisAssumption") }),
        ]
        if method.kind == .airflowPreview {
            var geometry = try JSONTreeCoding.encode(input.snapshot.geometry)
            if var g = geometry.fields {
                g["rooms"] = .array(
                    (g["rooms"]?.items ?? []).map {
                        var f = $0.fields ?? [:]
                        f.removeValue(forKey: "name")
                        f.removeValue(forKey: "northAngle")
                        return .object(f)
                    })
                g["obstacles"] = .array(
                    (g["obstacles"]?.items ?? []).map {
                        var f = $0.fields ?? [:]
                        f.removeValue(forKey: "name")
                        return .object(f)
                    })
                geometry = .object(g)
            }
            fields["geometry"] = try AnalysisCanonicalizer.value(
                geometry, schema: root["$defs"]?["ProjectGeometry"], root: root, registry: registry)
            fields["devices"] = .array(
                try input.snapshot.inputs.hvac.map { d in
                    .object([
                        "id": .string(d.id.uuidString.lowercased()),
                        "roomID": .string(d.roomID.uuidString.lowercased()),
                        "kind": .string(d.definition.kind),
                        "payloadVersion": .integer(Int64(d.definition.payloadVersion)),
                        "supplyPorts": .array(
                            try d.ports.filter { $0.role == .supply }.map { p in
                                .object([
                                    "id": .string(p.id.uuidString.lowercased()),
                                    "position": try typed(p.position, "Position3D"),
                                    "direction": try typed(p.direction, "Direction3D"),
                                ])
                            }),
                    ])
                })
            fields["targets"] = .array(
                try input.snapshot.inputs.usage.seats.map { seat in
                    var tree = try JSONTreeCoding.encode(seat).fields ?? [:]
                    tree.removeValue(forKey: "name")
                    return try AnalysisCanonicalizer.value(
                        .object(tree), schema: root["$defs"]?["Seat"], root: root, registry: registry)
                })
        }
        return .object(fields)
    }
}
