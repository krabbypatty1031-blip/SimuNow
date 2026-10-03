import Foundation
import SimuCore

public enum RoomCaptureConversion {
    /// User-confirmed bounding-box simplification, not an automatic CFD mesh or thermophysical model.
    public static func project(_ snapshot: RoomCaptureSnapshot) throws -> ProjectDocument {
        try WireSchema.validate(JSONTreeCoding.encode(snapshot), schema: NativeAnalysisCodec.schema(.roomCapture))
        let d = snapshot.roomDimensionsMeters
        guard snapshot.captureVersion == 1, snapshot.coordinateSystem == "rightHandedZUp", snapshot.furniture.count <= 128,
              [d.x,d.y,d.z,snapshot.appleOriginInDomain.x,snapshot.appleOriginInDomain.y,snapshot.appleOriginInDomain.z].allSatisfy(\.isFinite),
              d.x > 0, d.y > 0, d.z > 0, snapshot.source.kind == .scan else { throw ProjectDataError.contract("扫描尺寸、版本或坐标依据无效。") }
        let roomID = UUID()
        func length(_ value: Double) -> Length { .known(value: value, source: snapshot.source) }
        let room = Room(id: roomID, name: "扫描房间（包围盒待修正）", shape: try ExtensionRecord(RectangularRoom(dimensions:
            .init(width: length(d.x), depth: length(d.y), height: length(d.z)))), northAngle: .unknown(reason: "扫描世界轴不代表真实北向"),
            surfaces: SurfaceFace.allCases.map { .init(id: UUID(), face: $0) }, openings: [])
        let objects = try snapshot.furniture.enumerated().map { index, box in
            guard [box.origin.x,box.origin.y,box.origin.z,box.dimensions.x,box.dimensions.y,box.dimensions.z].allSatisfy(\.isFinite),
                  box.dimensions.x > 0, box.dimensions.y > 0, box.dimensions.z > 0 else { throw ProjectDataError.contract("扫描家具盒体无效。") }
            return Obstacle(id: UUID(), roomID: roomID, name: "扫描家具 \(index + 1)", shape: try ExtensionRecord(BoxObstacle(origin: box.origin,
                dimensions: .init(width: length(box.dimensions.x), depth: length(box.dimensions.y), height: length(box.dimensions.z)))))
        }
        let project = ProjectDocument(id: UUID(), name: "扫描项目", spaceType: .home, geometry: .init(rooms: [room], obstacles: objects),
                                      scenarios: [.unfinished(name: "基准方案（待标注设备与关注点）")])
        let report = try ProjectValidator().validate(project, registry: .builtIn)
        guard report.passes(.projectIntegrity) else { throw ProjectDataError.contract("扫描盒体不在房间范围内，请改用手动模型或修正扫描。") }
        return project
    }
}
