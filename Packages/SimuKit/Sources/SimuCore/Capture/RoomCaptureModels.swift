import Foundation

public struct CapturedGeometryBox: Codable, Equatable, Sendable {
    public let origin: Position3D
    public let dimensions: Position3D
    public init(origin: Position3D, dimensions: Position3D) { self.origin = origin; self.dimensions = dimensions }
}
public struct RoomCaptureSnapshot: Codable, Equatable, Sendable {
    public let captureVersion: Int
    public let captureID: UUID
    public let coordinateSystem: String
    public let appleOriginInDomain: Position3D
    public let roomDimensionsMeters: Position3D
    public let furniture: [CapturedGeometryBox]
    public let source: SourceRecord
    public init(captureID: UUID = UUID(), appleOriginInDomain: Position3D, roomDimensionsMeters: Position3D,
                furniture: [CapturedGeometryBox], source: SourceRecord) {
        captureVersion = 1; self.captureID = captureID; coordinateSystem = "rightHandedZUp"
        self.appleOriginInDomain = appleOriginInDomain; self.roomDimensionsMeters = roomDimensionsMeters
        self.furniture = furniture; self.source = source
    }
}
