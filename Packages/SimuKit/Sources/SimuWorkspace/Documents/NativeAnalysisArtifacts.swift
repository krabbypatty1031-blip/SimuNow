import Foundation
import SimuCore
import SimuSimulation

public enum NativeArtifactError: Error, Equatable, Sendable {
    case identityMismatch, invalidManifest, contentMismatch(String), collision(String), resourceLimit(String), unsupportedRecord
}
public struct NativeAnalysisArtifact: Equatable, Sendable {
    public let request: LocalAnalysisRequest
    public let result: LocalAnalysisResult
    public let manifest: AnalysisArtifactManifest
    public let inputData: Data
    public let resultData: Data
    public let manifestData: Data
    public var byteCount: Int { inputData.count + resultData.count + manifestData.count }
}
public struct NativeArtifactReadIssue: Equatable, Sendable {
    public let relativePath: String
    public let message: String
    public init(relativePath: String, message: String) { self.relativePath = relativePath; self.message = message }
}
public struct NativeArtifactReadResult: Equatable, Sendable {
    public let artifacts: [NativeAnalysisArtifact]
    public let issues: [NativeArtifactReadIssue]
}
/// CPU-only immutable codec. Call from a detached task for sizeable packages.
public struct NativeArtifactCodec: Sendable {
    public let registry: ModelRegistry
    public static let maximumInputBytes = 8*1024*1024
    public static let maximumResultBytes = 2*1024*1024
    public static let maximumManifestBytes = 64*1024
    public static let maximumConfigurationBytes = 1024*1024
    public static let maximumOwnedBytes = 32*1024*1024
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    public func make(request: LocalAnalysisRequest, result: LocalAnalysisResult) throws -> NativeAnalysisArtifact {
        guard request.identity == result.identity, request.method == result.method,
              result.assumptions == request.resolvedInput.adoptedAssumptions else { throw NativeArtifactError.identityMismatch }
        try AnalysisInputResolver(registry: registry).validate(request)
        let codec = NativeAnalysisCodec(registry: registry)
        let input = try codec.encodeRequest(request), output = try codec.encodeResult(result)
        guard input.count <= Self.maximumInputBytes, output.count <= Self.maximumResultBytes else { throw NativeArtifactError.resourceLimit("Native input/result exceeds budget") }
        let manifest = AnalysisArtifactManifest(runID: request.identity.runID, scenarioID: request.identity.scenarioID,
            projectID: request.resolvedInput.snapshot.projectID, files: [
                .init(relativePath: "input.json", byteCount: input.count, sha256: AnalysisHasher.sha256(input)),
                .init(relativePath: "result.json", byteCount: output.count, sha256: AnalysisHasher.sha256(output))])
        let data = try codec.encodeManifest(manifest)
        return .init(request: request, result: result, manifest: manifest, inputData: input, resultData: output, manifestData: data)
    }
    public func decode(_ files: [String:ProjectPackageEntry], expectedRunID: UUID, expectedProjectID: UUID) throws -> NativeAnalysisArtifact {
        func data(_ path: String, maximum: Int) throws -> Data {
            guard case .file(let data) = ProjectPackageEntry.directory(files).entry(at: path), data.count <= maximum else { throw NativeArtifactError.resourceLimit(path) }; return data
        }
        let manifestData = try data("manifest.json", maximum: Self.maximumManifestBytes)
        let codec = NativeAnalysisCodec(registry: registry), manifest = try codec.decodeManifest(manifestData)
        guard manifest.runID == expectedRunID, manifest.projectID == expectedProjectID else { throw NativeArtifactError.identityMismatch }
        for f in manifest.files {
            let maximum = f.relativePath == "input.json" ? Self.maximumInputBytes : f.relativePath == "result.json" ? Self.maximumResultBytes : 256*1024
            let content = try data(f.relativePath, maximum: maximum)
            guard content.count == f.byteCount, AnalysisHasher.sha256(content) == f.sha256 else { throw NativeArtifactError.contentMismatch(f.relativePath) }
        }
        let input = try data("input.json", maximum: Self.maximumInputBytes), output = try data("result.json", maximum: Self.maximumResultBytes)
        let request = try codec.decodeRequest(input), result = try codec.decodeResult(output)
        try AnalysisInputResolver(registry: registry).validate(request)
        guard request.identity == result.identity, request.identity.runID == manifest.runID,
              request.identity.scenarioID == manifest.scenarioID, request.method == result.method,
              result.assumptions == request.resolvedInput.adoptedAssumptions else { throw NativeArtifactError.identityMismatch }
        return .init(request: request, result: result, manifest: manifest, inputData: input, resultData: output, manifestData: manifestData)
    }
    public func read(entries: [String:ProjectPackageEntry], projectID: UUID) -> NativeArtifactReadResult {
        var artifacts: [NativeAnalysisArtifact] = [], issues: [NativeArtifactReadIssue] = []
        guard case .directory(let runs) = entries["runs"] else { return .init(artifacts: [], issues: []) }
        for key in runs.keys.sorted() {
            guard let runID = UUID(uuidString: key), case .directory(let run) = runs[key],
                  case .directory(let native) = run["native-analysis"] else { continue }
            do {
                let artifact = try decode(native, expectedRunID: runID, expectedProjectID: projectID)
                artifacts.append(artifact)
            } catch {
                issues.append(.init(relativePath: "runs/\(key)/native-analysis", message: "分析附件未作为有效结果载入，原文件保持：\(error)"))
            }
        }
        return .init(artifacts: artifacts, issues: issues)
    }
}
public extension SimuNowDocument {
    var analysisConfigurationData: Data? {
        if case .file(let data) = ProjectPackageEntry.directory(preservedEntries).entry(at: "analysis/configuration.json") { return data }; return nil
    }
    func analysisConfigurationStore(registry: ModelRegistry = .builtIn) throws -> AnalysisConfigurationStore {
        guard let data = analysisConfigurationData else { return .init(projectID: project.id) }
        guard data.count <= NativeArtifactCodec.maximumConfigurationBytes else { throw NativeArtifactError.resourceLimit("configuration.json") }
        let store = try NativeAnalysisCodec(registry: registry).decodeConfiguration(data)
        guard store.projectID == project.id else { throw NativeArtifactError.identityMismatch }; return store
    }
    /// Returns a full next document value. Caller merges with the latest binding, never an old captured value.
    func updatingAnalysisConfiguration(_ configuration: AnalysisConfigurationStore) throws -> Self {
        guard configuration.projectID == project.id else { throw NativeArtifactError.identityMismatch }
        if let current = analysisConfigurationData {
            let existing = try NativeAnalysisCodec().decodeConfiguration(current)
            guard existing.projectID == project.id else { throw NativeArtifactError.identityMismatch }
        } // Future/corrupt records cannot be overwritten implicitly.
        let data = try NativeAnalysisCodec().encodeConfiguration(configuration)
        guard data.count <= NativeArtifactCodec.maximumConfigurationBytes else { throw NativeArtifactError.resourceLimit("configuration.json") }
        if data == analysisConfigurationData { return self }
        var entries = preservedEntries
        try entries.setNativeEntry(.file(data), at: ["analysis","configuration.json"], allowReplace: true)
        try Self.validateOwnedNativeBudget(entries)
        return try replacingPreservedEntries(entries)
    }
    func appendingNativeAnalysis(_ artifact: NativeAnalysisArtifact, expectedProjectID: UUID) throws -> Self {
        guard project.id == expectedProjectID, artifact.manifest.projectID == project.id else { throw NativeArtifactError.identityMismatch }
        // Artifacts have no public initializer; only the validating immutable codec can construct them.
        let data: [String:ProjectPackageEntry] = ["input.json": .file(artifact.inputData), "result.json": .file(artifact.resultData), "manifest.json": .file(artifact.manifestData)]
        var entries = preservedEntries
        try entries.setNativeEntry(.directory(data), at: ["runs",artifact.request.identity.runID.uuidString.lowercased(),"native-analysis"], allowReplace: false)
        try Self.validateOwnedNativeBudget(entries)
        return try replacingPreservedEntries(entries)
    }
    func applyingWorkspaceState(_ state: WorkspaceProjectState) throws -> Self {
        var metadata = metadata
        metadata.baselineScenarioID = state.baselineScenarioID
        metadata.templateID = state.templateID; metadata.templateVersion = state.templateVersion
        var entries = preservedEntries
        if state.project.id != project.id, let bytes = analysisConfigurationData,
           let owned = try? NativeAnalysisCodec().decodeConfiguration(bytes), owned.projectID == project.id,
           case .directory(var analysis) = entries["analysis"] {
            // Explicit whole-project replacement clears only this project's supported configuration.
            analysis.removeValue(forKey: "configuration.json"); entries["analysis"] = .directory(analysis)
        }
        var next = try replacingNativeInputState(project: state.project, metadata: metadata, entries: entries)
        if let configuration = state.analysisConfiguration { next = try next.updatingAnalysisConfiguration(configuration) }
        else if let bytes = next.analysisConfigurationData,
                let owned = try? NativeAnalysisCodec().decodeConfiguration(bytes), owned.projectID == next.project.id {
            var entries = next.preservedEntries
            if case .directory(var analysis) = entries["analysis"] {
                analysis.removeValue(forKey: "configuration.json"); entries["analysis"] = .directory(analysis)
                next = try next.replacingPreservedEntries(entries)
            }
        }
        return next
    }
    private static func validateOwnedNativeBudget(_ entries: [String:ProjectPackageEntry]) throws {
        var total = 0
        if case .file(let config) = ProjectPackageEntry.directory(entries).entry(at: "analysis/configuration.json"),
           let node = try? JSONValue(data: config), node["storeVersion"]?.double == 1 { total += config.count }
        if case .directory(let runs) = entries["runs"] {
            for entry in runs.values {
                guard case .directory(let run) = entry, case .directory(let native) = run["native-analysis"],
                      case .file(let manifest) = native["manifest.json"], manifest.count <= NativeArtifactCodec.maximumManifestBytes,
                      let node = try? JSONValue(data: manifest), node["owner"]?.string == "com.simunow.native-analysis", node["artifactVersion"]?.double == 1 else { continue }
                total += manifest.count
                for file in node["files"]?.items ?? [] {
                    if let path = file["relativePath"]?.string, case .file(let data) = ProjectPackageEntry.directory(native).entry(at: path) { total += data.count }
                }
                guard total <= NativeArtifactCodec.maximumOwnedBytes else { throw NativeArtifactError.resourceLimit("Recognized native analysis budget exceeded") }
            }
        }
        guard total <= NativeArtifactCodec.maximumOwnedBytes else { throw NativeArtifactError.resourceLimit("Recognized native analysis budget exceeded") }
    }
}
private extension Dictionary where Key == String, Value == ProjectPackageEntry {
    mutating func setNativeEntry(_ value: ProjectPackageEntry, at components: [String], allowReplace: Bool) throws {
        guard let key = components.first else { throw NativeArtifactError.invalidManifest }
        if components.count == 1 {
            if self[key] != nil && !allowReplace { throw NativeArtifactError.collision(key) }
            self[key] = value; return
        }
        var nested: [String:ProjectPackageEntry] = [:]
        if let current = self[key] {
            guard case .directory(let directory) = current else { throw NativeArtifactError.collision(key) }; nested = directory
        }
        try nested.setNativeEntry(value, at: Array(components.dropFirst()), allowReplace: allowReplace)
        self[key] = .directory(nested)
    }
}
