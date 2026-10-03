import Foundation
import SimuCore
import SimuVisualization
import SimuWorkspace
import Testing

@Test func civilClockConversionsPreserveDayEndAndIncompleteText() {
    #expect(InputDisplay.minuteText("09:05") == "545")
    #expect(InputDisplay.clock("545") == "09:05")
    #expect(InputDisplay.minuteText("24:00") == "1440")
    #expect(InputDisplay.clock("1440") == "24:00")
    for input in ["24:01", "09:", "09:60", "unfinished"] {
        #expect(InputDisplay.minuteText(input) == input)
        #expect(InputDisplay.minutes(InputDisplay.minuteText(input)) == nil)
    }
    #expect(InputDisplay.minutes("1441") == nil)
    #expect(InputDisplay.clock("unfinished") == "unfinished")
}

@Test func fieldNavigationDisambiguatesRoomFurnitureAndOpeningDimensions() {
    #expect(FieldNavigation.field("/geometry/rooms/0/shape/payload/dimensions/width/value") == "宽度（X）")
    #expect(FieldNavigation.field("/geometry/obstacles/1/shape/payload/dimensions/width/value") == "宽度 X")
    #expect(FieldNavigation.field("/geometry/rooms/0/openings/2/width/value") == "宽度（U）")
    #expect(FieldNavigation.field("/scenarios/0/inputs/hvac/0/ports/1/direction") == "水平角（°，+X 向 +Y）")
    #expect(FieldNavigation.field("/future/unrecognized") == nil)
    #expect(FieldNavigation.ordinal("/scenarios/0/inputs/usage/equipment/0/schedule/intervals/2/startMinute") == 2)
    #expect(FieldNavigation.ordinal("/scenarios/0/evaluation/cost/tariffs/1/rate/value") == 1)
    #expect(FieldNavigation.ordinal("/scenarios/0/inputs/hvac/0/ports/1/area/value") == nil)
}

@Test func displayPanIsBoundedAndPreservesCameraOrientationAndDistance() {
    let bounds = GeometryBounds(origin: .init(x: 0, y: 0, z: 0), size: .init(x: 6, y: 4, z: 3))
    var camera = RoomCameraState.fitting(bounds: bounds, aspectRatio: 1.5)
    let original = camera
    camera.pan(horizontal: 0.1, vertical: 0.1, roomBounds: bounds)
    #expect(camera.target != original.target)
    #expect(camera.distance == original.distance)
    #expect(camera.yawDegrees == original.yawDegrees && camera.pitchDegrees == original.pitchDegrees)
    let finite = camera
    camera.pan(horizontal: .infinity, vertical: 0, roomBounds: bounds)
    #expect(camera == finite)
    camera.pan(horizontal: 1e100, vertical: -1e100, roomBounds: bounds)
    #expect([camera.target.x, camera.target.y, camera.target.z].allSatisfy { $0.isFinite })
    let margin = RoomCameraState.diagonal(bounds)
    #expect(camera.target.x >= -margin && camera.target.x <= bounds.size.x + margin)
    #expect(camera.ray(x: 50, y: 50, viewportWidth: 100, viewportHeight: 100) != nil)
}
