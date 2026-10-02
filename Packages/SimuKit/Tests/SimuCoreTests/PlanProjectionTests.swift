import Foundation
import Testing
import SimuCore
import SimuVisualization

@Test func planProjectionFitsMetresAndInvertsScreenYAxis() throws {
    let bounds = GeometryBounds(origin: .init(x: 1, y: 2, z: 0), size: .init(x: 6, y: 4, z: 3))
    let projection = try #require(PlanProjection(bounds: bounds, screenWidth: 648, screenHeight: 448))
    #expect(projection.scale == 100)
    let lowerLeft = projection.project(.init(x: 1, y: 2, z: 0)), upperRight = projection.project(.init(x: 7, y: 6, z: 0))
    #expect(lowerLeft == .init(x: 24, y: 424))
    #expect(upperRight == .init(x: 624, y: 24))
    for point in [Position3D(x: 1.25, y: 4.7, z: 1.1), Position3D(x: 7, y: 6, z: 2)] {
        let restored = projection.unproject(projection.project(point), z: point.z)
        #expect(abs(restored.x - point.x) < 1e-12 && abs(restored.y - point.y) < 1e-12 && restored.z == point.z)
    }
    #expect(!projection.contains(.init(x: 0, y: 0)))
    #expect(PlanProjection(bounds: bounds, screenWidth: 40, screenHeight: 20) == nil)
    #expect(PlanProjection(bounds: .init(origin: bounds.origin, size: .init(x: 0, y: 4, z: 3)), screenWidth: 640, screenHeight: 480) == nil)
}
@Test func planAirflowAnglesProduceUnitDirectionsAndPreserveAxes() throws {
    #expect(try AirflowDirection.unit(yawDegrees: 0, pitchDegrees: 0) == .init(x: 1, y: 0, z: 0))
    let y = try AirflowDirection.unit(yawDegrees: 90, pitchDegrees: 0)
    #expect(abs(y.x) < 1e-12 && abs(y.y - 1) < 1e-12)
    for yaw in [-720.0, -90, 0, 40, 90, 270, 720] {
        for pitch in [-90.0, -30, 0, 45, 90] {
            let direction = try AirflowDirection.unit(yawDegrees: yaw, pitchDegrees: pitch)
            let norm = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
            #expect(abs(norm - 1) < 1e-12)
            let angles = AirflowDirection.angles(direction)
            let restored = try AirflowDirection.unit(yawDegrees: angles.yaw, pitchDegrees: angles.pitch)
            #expect(abs(restored.x - direction.x) < 1e-12 && abs(restored.y - direction.y) < 1e-12 && abs(restored.z - direction.z) < 1e-12)
        }
    }
    #expect(throws: (any Error).self) { try AirflowDirection.unit(yawDegrees: .nan, pitchDegrees: 0) }
    #expect(throws: (any Error).self) { try AirflowDirection.unit(yawDegrees: 0, pitchDegrees: 91) }
    #expect(RoomPlanSelection(kind: .sample, objectID: UUID()).id.hasPrefix("sample:"))
}
