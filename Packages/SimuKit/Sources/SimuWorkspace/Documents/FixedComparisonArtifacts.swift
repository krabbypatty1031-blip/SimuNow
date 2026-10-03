import Foundation
import SimuCore
import SimuSimulation

public struct FixedComparisonArtifact: Sendable {
    public let record: ComparisonRecord
    public let data: Data
    fileprivate let parentFiles: [String: Data]
    fileprivate init(record: ComparisonRecord, data: Data, parentFiles: [String: Data]) {
        self.record = record; self.data = data; self.parentFiles = parentFiles
    }
}
public enum FixedComparisonArtifacts {
    public static func make(_ snapshot: ComparisonSnapshot, entries: [String: ProjectPackageEntry]) throws -> FixedComparisonArtifact {
        var parents: [NativeAnalysisArtifact] = []; var files: [String: Data] = [:]; var costs: [CostEvaluationRecord] = []
        for reference in snapshot.runs {
            try Task.checkCancellation()
            let artifact = try NativeArtifactCodec().load(runID: reference.runID, entries: entries, projectID: snapshot.projectID)
            parents.append(artifact)
            let root = "runs/\(reference.runID.uuidString.lowercased())/native-analysis/"
            files[root + "input.json"] = artifact.inputData; files[root + "result.json"] = artifact.resultData
            if let hash = reference.evaluationHash {
                let cost = try NativeCostEvaluationCodec.load(hash: hash, parent: artifact, entries: entries)
                costs.append(cost)
                if case .file(let bytes) = ProjectPackageEntry.directory(entries).entry(at: root + "evaluations/\(hash).json") {
                    files[root + "evaluations/\(hash).json"] = bytes
                }
            }
        }
        let record = try ComparisonRecordCodec.make(snapshot: snapshot, requests: parents.map(\.request), results: parents.map(\.result),
            inputFiles: Dictionary(uniqueKeysWithValues: parents.map { ($0.request.identity.runID, $0.inputData) }),
            resultFiles: Dictionary(uniqueKeysWithValues: parents.map { ($0.result.identity.runID, $0.resultData) }), costs: costs)
        return .init(record: record, data: try ComparisonRecordCodec.encode(record), parentFiles: files)
    }
    public static func load(_ data: Data, entries: [String: ProjectPackageEntry], projectID: UUID) throws -> FixedComparisonArtifact {
        let record = try ComparisonRecordCodec.decode(data)
        guard record.snapshot.projectID == projectID else { throw NativeArtifactError.identityMismatch }
        let verified = try make(record.snapshot, entries: entries)
        guard verified.record == record else { throw NativeArtifactError.contentMismatch("comparison references") }
        return verified
    }
    public static func data(entries: [String: ProjectPackageEntry]) -> [(UUID, Data)] {
        guard case .directory(let files) = ProjectPackageEntry.directory(entries).entry(at: "analysis/comparisons") else { return [] }
        return files.keys.sorted().compactMap { key in
            guard key.hasSuffix(".json"), let id = UUID(uuidString: String(key.dropLast(5))),
                  case .file(let bytes) = files[key], bytes.count <= ComparisonRecordCodec.maximumBytes else { return nil }
            return (id, bytes)
        }
    }
}
public extension SimuNowDocument {
    func appendingComparison(_ artifact: FixedComparisonArtifact) throws -> Self {
        guard project.id == artifact.record.snapshot.projectID else { throw NativeArtifactError.identityMismatch }
        let root = ProjectPackageEntry.directory(preservedEntries)
        // Background validation produced these exact immutable parent bytes. Merge the latest document.
        for (path, bytes) in artifact.parentFiles {
            guard root.entry(at: path) == .file(bytes) else { throw NativeArtifactError.contentMismatch(path) }
        }
        let path = ["analysis", "comparisons", artifact.record.id.uuidString.lowercased() + ".json"]
        if let current = root.entry(at: path.joined(separator: "/")) {
            guard current == .file(artifact.data) else { throw NativeArtifactError.collision("comparison") }; return self
        }
        var entries = preservedEntries
        try entries.setNativeEntry(.file(artifact.data), at: path, allowReplace: false)
        try Self.validateOwnedNativeBudget(entries)
        return try replacingPreservedEntries(entries)
    }
}
