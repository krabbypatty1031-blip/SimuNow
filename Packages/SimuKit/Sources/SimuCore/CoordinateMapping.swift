import Foundation

/// Apple / RealityKit style Y-up display metres ↔ public Z-up computation metres.
public enum CoordinateMapping: Sendable {
    public static func toComputation(_ display: Position3D) -> Position3D {
        Position3D(x: display.x, y: -display.z, z: display.y)
    }

    public static func toDisplay(_ computation: Position3D) -> Position3D {
        Position3D(x: computation.x, y: computation.z, z: -computation.y)
    }
}
