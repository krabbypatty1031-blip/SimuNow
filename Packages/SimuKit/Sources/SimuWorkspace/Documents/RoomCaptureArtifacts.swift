import Foundation
import SimuCore
import SimuSimulation

public struct RoomCaptureArtifact: Equatable, Sendable {
    public let project: ProjectDocument
    public let snapshot: RoomCaptureSnapshot
    public let snapshotData: Data
    public let originalData: Data
    public let originalSHA256: String
    private init(project: ProjectDocument, snapshot: RoomCaptureSnapshot, snapshotData: Data, originalData: Data, originalSHA256: String) {
        self.project = project; self.snapshot = snapshot; self.snapshotData = snapshotData
        self.originalData = originalData; self.originalSHA256 = originalSHA256
    }
    public static func make(_ snapshot: RoomCaptureSnapshot, original: Data) throws -> Self {
        guard original.count <= 8*1024*1024, !original.isEmpty else { throw NativeArtifactError.resourceLimit("room capture") }
        _ = try JSONValue(data: original)
        let project = try RoomCaptureConversion.project(snapshot), data = try JSONTreeCoding.encode(snapshot).data()
        guard data.count <= 256*1024 else { throw NativeArtifactError.resourceLimit("capture conversion") }
        return .init(project: project, snapshot: snapshot, snapshotData: data, originalData: original, originalSHA256: AnalysisHasher.sha256(original))
    }
}
extension Dictionary where Key == String, Value == ProjectPackageEntry {
    mutating func appendRoomCapture(_ artifact: RoomCaptureArtifact) throws {
        let manifest: JSONValue = .object(["owner": .string("com.simunow.capture"), "captureVersion": .number("1"),
            "projectID": .string(artifact.project.id.uuidString.lowercased()), "captureID": .string(artifact.snapshot.captureID.uuidString.lowercased()),
            "originalByteCount": .number(String(artifact.originalData.count)), "originalSHA256": .string(artifact.originalSHA256),
            "snapshotSHA256": .string(AnalysisHasher.sha256(artifact.snapshotData))])
        let files: [String: ProjectPackageEntry] = ["geometry.json": .file(artifact.snapshotData), "roomplan.json": .file(artifact.originalData), "manifest.json": .file(try manifest.data())]
        let path = ["captures", artifact.snapshot.captureID.uuidString.lowercased()]
        if let old = ProjectPackageEntry.directory(self).entry(at: path.joined(separator: "/")) {
            guard old == .directory(files) else { throw NativeArtifactError.collision("capture") }; return
        }
        try setNativeEntry(.directory(files), at: path, allowReplace: false)
    }
}
