import Foundation
import SimuCore

public enum ComparisonRecordCodec {
    public static let maximumBytes = 256 * 1024
    public static func make(snapshot: ComparisonSnapshot, requests: [LocalAnalysisRequest],
                            results: [LocalAnalysisResult], inputFiles: [UUID: Data], resultFiles: [UUID: Data],
                            costs: [CostEvaluationRecord] = []) throws -> ComparisonRecord {
        guard snapshot.runs.count >= 2, snapshot.runs.count <= 3,
              requests.count == snapshot.runs.count, results.count == requests.count else {
            throw ProjectDataError.contract("固定比较需要基准和一至两个候选的完整证据。")
        }
        var references: [ComparisonEvidenceReference] = []
        var evidence: [FixedEstimateEvidence] = []
        for reference in snapshot.runs {
            guard let request = requests.first(where: { $0.identity.runID == reference.runID }),
                  let result = results.first(where: { $0.identity.runID == reference.runID }),
                  request.resolvedInput.snapshot.projectID == snapshot.projectID,
                  request.identity == result.identity, result.identity.scenarioID == reference.scenarioID,
                  result.identity.inputHash == reference.inputHash, result.method == reference.method,
                  let input = inputFiles[reference.runID], let output = resultFiles[reference.runID],
                  try NativeAnalysisCodec().decodeRequest(input) == request,
                  try NativeAnalysisCodec().decodeResult(output) == result else {
                throw ProjectDataError.contract("固定比较引用的运行、方法或文件不一致。")
            }
            let cost = costs.first { $0.parentIdentity.runID == reference.runID && $0.evaluationHash == reference.evaluationHash }
            guard reference.evaluationHash == nil || cost != nil else { throw ProjectDataError.contract("固定比较缺少费用评价证据。") }
            evidence.append(.init(request: request, result: result, currentInputHash: reference.inputHash, cost: cost))
            references.append(.init(run: reference, inputSHA256: AnalysisHasher.sha256(input), resultSHA256: AnalysisHasher.sha256(output)))
        }
        let verified = try snapshotFor(evidence, comparisonID: snapshot.comparisonID, decisions: snapshot.decisionVariables ?? [])
        guard verified == snapshot else { throw ProjectDataError.contract("固定比较结论与所引用证据不一致。") }
        let unsigned = ComparisonRecord(snapshot: snapshot, references: references, bodyHash: String(repeating: "0", count: 64))
        let record = ComparisonRecord(snapshot: snapshot, references: references, bodyHash: try bodyHash(unsigned))
        _ = try encode(record); return record
    }
    public static func snapshotFor(_ evidence: [FixedEstimateEvidence], comparisonID: UUID = UUID(), decisions: [String]) throws -> ComparisonSnapshot {
        guard (2...3).contains(evidence.count), Set(evidence.map { $0.result.identity.scenarioID }).count == evidence.count else {
            throw ProjectDataError.contract("请选择独立的基准与候选方案。")
        }
        if evidence.count == 2 { return try EstimateComparator.compare(baseline: evidence[0], candidate: evidence[1], decisionVariables: decisions, comparisonID: comparisonID) }
        guard evidence.allSatisfy({ $0.result.method.kind == .airflowPreview }) else { throw ProjectDataError.contract("三方案固定比较目前只支持方向规则。") }
        let pairs = try evidence.dropFirst().map { try EstimateComparator.compare(baseline: evidence[0], candidate: $0, decisionVariables: decisions) }
        let refs = evidence.map { ComparisonRunReference(runID: $0.result.identity.runID, scenarioID: $0.result.identity.scenarioID, inputHash: $0.result.identity.inputHash, method: $0.result.method) }
        let reasons = pairs.flatMap(\.incomparableReasons)
        let context = try JSONTreeCoding.encode(evidence.map(\.request.resolvedInput))
        let hash = AnalysisHasher.sha256(try AnalysisCanonicalizer.bytes(AnalysisCanonicalizer.value(context, schema: nil, root: .object([:]))))
        return .init(comparisonID: comparisonID, projectID: evidence[0].request.resolvedInput.snapshot.projectID,
            runs: refs, comparisonContextHash: hash, comparableItems: reasons.isEmpty ? ["qualitativePathRelations"] : [],
            incomparableReasons: reasons, decisionVariables: decisions)
    }
    public static func encode(_ record: ComparisonRecord) throws -> Data {
        guard record.bodyHash == (try bodyHash(record)) else { throw ProjectDataError.contract("固定比较 bodyHash 不符。") }
        let data = try NativeAnalysisCodec().encodeComparisonRecord(record)
        guard data.count <= maximumBytes else { throw ProjectDataError.contract("固定比较超过 256 KiB。") }; return data
    }
    public static func decode(_ data: Data) throws -> ComparisonRecord {
        guard data.count <= maximumBytes else { throw ProjectDataError.contract("固定比较超过 256 KiB。") }
        let record = try NativeAnalysisCodec().decodeComparisonRecord(data)
        guard record.bodyHash == (try bodyHash(record)) else { throw ProjectDataError.contract("固定比较 bodyHash 不符。") }; return record
    }
    private static func bodyHash(_ record: ComparisonRecord) throws -> String {
        var body = try JSONTreeCoding.encode(record).fields!
        body.removeValue(forKey: "bodyHash")
        return AnalysisHasher.sha256(try AnalysisCanonicalizer.bytes(AnalysisCanonicalizer.value(.object(body), schema: nil, root: .object([:]))))
    }
}
