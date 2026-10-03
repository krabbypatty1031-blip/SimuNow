import Foundation
import SimuCore
import SimuSimulation

public struct CalibrationArtifact: Sendable {
    public let record: JetCalibrationRecord
    public let data: Data
    fileprivate let datasetData: Data
    private init(record: JetCalibrationRecord, data: Data, datasetData: Data) { self.record = record; self.data = data; self.datasetData = datasetData }
    public static func make(_ input: FiniteJetCalibrationInput) throws -> Self {
        let record = try FiniteJetCalibration.calibrate(input)
        let tree = try JSONTreeCoding.encode(record)
        try WireSchema.validate(tree, schema: NativeAnalysisCodec.schema(.jetCalibration))
        let data = try tree.data()
        guard data.count <= 256*1024 else { throw NativeArtifactError.resourceLimit("calibration") }
        return .init(record: record, data: data, datasetData: try MeasurementDatasetCodec.encode(input.dataset))
    }
    public static func index(entries: [String: ProjectPackageEntry], datasetID: UUID? = nil) -> [UUID] {
        guard case .directory(let files) = ProjectPackageEntry.directory(entries).entry(at: "analysis/calibrations") else { return [] }
        return files.keys.sorted().compactMap { key in
            guard key.hasSuffix(".json"), let id = UUID(uuidString: String(key.dropLast(5))) else { return nil }
            if let datasetID {
                guard case .file(let bytes) = files[key], bytes.count <= 256*1024,
                      let tree = try? JSONValue(data: bytes), let value = tree["datasetID"]?.string,
                      UUID(uuidString: value) == datasetID else { return nil }
            }
            return id
        }
    }
    public static func load(id: UUID, entries: [String: ProjectPackageEntry], projectID: UUID) throws -> Self {
        let path = "analysis/calibrations/\(id.uuidString.lowercased()).json"
        guard case .file(let data) = ProjectPackageEntry.directory(entries).entry(at: path), data.count <= 256*1024 else { throw NativeArtifactError.contentMismatch(path) }
        let tree = try JSONValue(data: data)
        try WireSchema.validate(tree, schema: NativeAnalysisCodec.schema(.jetCalibration))
        let record = try JSONTreeCoding.decode(JetCalibrationRecord.self, from: tree)
        guard record.id == id, record.projectID == projectID else { throw NativeArtifactError.identityMismatch }
        let dataset = try MeasurementArtifact.load(id: record.datasetID, entries: entries, projectID: projectID)
        guard AnalysisHasher.sha256(dataset.data) == record.datasetSHA256 else { throw NativeArtifactError.contentMismatch("calibration dataset") }
        let input = FiniteJetCalibrationInput(dataset: dataset.dataset, deviceID: record.deviceID, geometrySHA256: record.geometrySHA256,
            origin: record.origin, direction: record.direction, outletRadiusMeters: record.outletRadiusMeters,
            maximumDistanceMeters: record.maximumDistanceMeters, maximumValidationRMSE: record.maximumValidationRMSE)
        let verified = try FiniteJetCalibration.calibrate(input, recordID: record.id)
        guard verified == record else { throw NativeArtifactError.contentMismatch("calibration evidence") }
        return .init(record: record, data: data, datasetData: dataset.data)
    }
}
public extension SimuNowDocument {
    func appendingCalibration(_ artifact: CalibrationArtifact) throws -> Self {
        guard artifact.record.projectID == project.id,
              ProjectPackageEntry.directory(preservedEntries).entry(at: "measurements/\(artifact.record.datasetID.uuidString.lowercased())/data.json") == .file(artifact.datasetData) else { throw NativeArtifactError.identityMismatch }
        let path = ["analysis", "calibrations", artifact.record.id.uuidString.lowercased() + ".json"]
        if let bytes = ProjectPackageEntry.directory(preservedEntries).entry(at: path.joined(separator: "/")) {
            guard bytes == .file(artifact.data) else { throw NativeArtifactError.collision("calibration") }; return self
        }
        var entries = preservedEntries
        try entries.setNativeEntry(.file(artifact.data), at: path, allowReplace: false)
        try Self.validateOwnedNativeBudget(entries)
        return try replacingPreservedEntries(entries)
    }
}
