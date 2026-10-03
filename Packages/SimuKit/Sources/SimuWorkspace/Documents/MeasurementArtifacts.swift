import Foundation
import SimuCore
import SimuSimulation

private struct MeasurementManifest: Codable, Equatable, Sendable {
    let artifactVersion: Int
    let owner: String
    let datasetID: UUID
    let projectID: UUID
    let byteCount: Int
    let sha256: String
    let sourceSHA256: String
}
public struct MeasurementArtifact: Sendable {
    public let dataset: MeasurementDataset
    public let data: Data
    public let manifest: Data
    private init(dataset: MeasurementDataset, data: Data, manifest: Data) { self.dataset = dataset; self.data = data; self.manifest = manifest }
    public static func make(_ dataset: MeasurementDataset) throws -> Self {
        let data = try MeasurementDatasetCodec.encode(dataset)
        let manifest = MeasurementManifest(artifactVersion: 1, owner: "com.simunow.measurements", datasetID: dataset.id,
            projectID: dataset.projectID, byteCount: data.count, sha256: AnalysisHasher.sha256(data), sourceSHA256: dataset.sourceSHA256)
        return .init(dataset: dataset, data: data, manifest: try JSONTreeCoding.encode(manifest).data())
    }
    public static func load(id: UUID, entries: [String: ProjectPackageEntry], projectID: UUID) throws -> Self {
        let root = "measurements/\(id.uuidString.lowercased())/"
        guard case .file(let manifestBytes) = ProjectPackageEntry.directory(entries).entry(at: root + "manifest.json"), manifestBytes.count <= 4096,
              case .file(let data) = ProjectPackageEntry.directory(entries).entry(at: root + "data.json"), data.count <= 8*1024*1024 else { throw NativeArtifactError.contentMismatch(root) }
        let tree = try JSONValue(data: manifestBytes)
        guard Set(tree.fields?.keys.map { $0 } ?? []) == Set(["artifactVersion", "owner", "datasetID", "projectID", "byteCount", "sha256", "sourceSHA256"]) else { throw NativeArtifactError.invalidManifest }
        let manifest = try JSONTreeCoding.decode(MeasurementManifest.self, from: tree)
        guard manifest.artifactVersion == 1, manifest.owner == "com.simunow.measurements", manifest.projectID == projectID,
              manifest.datasetID == id, manifest.byteCount == data.count, manifest.sha256 == AnalysisHasher.sha256(data) else { throw NativeArtifactError.contentMismatch(root) }
        let dataset = try MeasurementDatasetCodec.decode(data)
        guard dataset.id == id, dataset.projectID == projectID, dataset.sourceSHA256 == manifest.sourceSHA256 else { throw NativeArtifactError.identityMismatch }
        return .init(dataset: dataset, data: data, manifest: manifestBytes)
    }
    public static func index(entries: [String: ProjectPackageEntry]) -> [UUID] {
        guard case .directory(let files) = entries["measurements"] else { return [] }
        return files.keys.sorted().compactMap(UUID.init(uuidString:))
    }
}
public extension SimuNowDocument {
    func appendingMeasurements(_ artifact: MeasurementArtifact) throws -> Self {
        guard artifact.dataset.projectID == project.id else { throw NativeArtifactError.identityMismatch }
        var entries = preservedEntries
        let path = ["measurements", artifact.dataset.id.uuidString.lowercased()]
        let files: [String: ProjectPackageEntry] = ["data.json": .file(artifact.data), "manifest.json": .file(artifact.manifest)]
        if let existing = ProjectPackageEntry.directory(entries).entry(at: path.joined(separator: "/")) {
            guard existing == .directory(files) else { throw NativeArtifactError.collision("measurement") }; return self
        }
        try entries.setNativeEntry(.directory(files), at: path, allowReplace: false)
        try Self.validateOwnedNativeBudget(entries)
        return try replacingPreservedEntries(entries)
    }
}
public actor MeasurementFileIO {
    public init() {}
    public func readCSV(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              (properties.fileSize ?? Int.max) <= MeasurementCSVImporter.maximumBytes else { throw ProjectDataError.contract("请选择至多 4 MiB 的普通 CSV 文件。") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var data = Data()
        while let bytes = try handle.read(upToCount: 65536), !bytes.isEmpty {
            try Task.checkCancellation()
            guard data.count + bytes.count <= MeasurementCSVImporter.maximumBytes else { throw ProjectDataError.contract("CSV 超过导入预算。") }; data.append(bytes)
        }
        return data
    }
}
