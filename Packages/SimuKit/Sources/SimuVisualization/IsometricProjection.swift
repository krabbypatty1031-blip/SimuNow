import CoreGraphics
import Foundation
import SimuCore

/// Orthographic camera for the room wireframe. Computation Z-up metres go
/// in; screen points (x right, y down) come out. The axis convention itself
/// is owned by `CoordinateMapping` (Z-up computation -> Y-up display); this
/// projection only rotates about display axes, so no second axis convention
/// can diverge.
public struct IsometricProjection: Sendable {
    /// Rotation about the display Y (up) axis; drag rotates the room.
    public var yawRadians: Double
    /// Fixed downward look angle; keeps floors and ceilings readable.
    public var pitchRadians: Double

    public init(yawRadians: Double, pitchRadians: Double = .pi / 6) {
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
    }

    public func screenPoint(_ computation: Position3D) -> CGPoint {
        let display = CoordinateMapping.toDisplay(computation)
        // Yaw about display Y.
        let cosYaw = cos(yawRadians)
        let sinYaw = sin(yawRadians)
        let x1 = display.x * cosYaw + display.z * sinYaw
        let z1 = -display.x * sinYaw + display.z * cosYaw
        // Pitch about display X, looking down.
        let cosPitch = cos(pitchRadians)
        let sinPitch = sin(pitchRadians)
        let y2 = display.y * cosPitch - z1 * sinPitch
        // Screen space: x to the right, y downward.
        return CGPoint(x: x1, y: -y2)
    }

    /// Projected room box corners, index-aligned with `RoomScene.roomCorners`.
    public func roomCorners(_ scene: RoomScene) -> [CGPoint] {
        scene.roomCorners.map(screenPoint)
    }

    /// Projected corners of a wall patch rectangle (4 points, closed shape).
    public func patchCorners(_ patch: WallPatchScene, in scene: RoomScene) -> [CGPoint] {
        scene.patchCorners(patch).map(screenPoint)
    }
}
