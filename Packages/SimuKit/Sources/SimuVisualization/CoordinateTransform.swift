import Foundation
import SimuCore

/// Right-handed Z-up domain to right-handed Y-up Apple display coordinates.
public enum CoordinateTransform {
    public static func toApple(_ p: Position3D) -> Position3D { .init(x:p.x,y:p.z,z:-p.y) }
    public static func toDomain(_ p: Position3D) -> Position3D { .init(x:p.x,y:-p.z,z:p.y) }
    public static func toApple(_ d: Direction3D) -> Direction3D { .init(x:d.x,y:d.z,z:-d.y) }
    public static func toDomain(_ d: Direction3D) -> Direction3D { .init(x:d.x,y:-d.z,z:d.y) }
    public static func toApple(_ d: Displacement3D) -> Displacement3D { .init(x:d.x,y:d.z,z:-d.y) }
    public static func toDomain(_ d: Displacement3D) -> Displacement3D { .init(x:d.x,y:-d.z,z:d.y) }
}
