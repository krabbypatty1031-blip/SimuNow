import Foundation
import simd
import SimuCore

/// Something the 3D preview can drag. The identifier matches the project entity.
public enum RoomPreviewItem: Hashable, Sendable {
    case seat(UUID)
    case obstacle(UUID)
    case device(UUID)
    case equipment(UUID)
}

/// How far attached points extend from the anchor, in domain metres.
/// `low` is ≤ 0 and `high` is ≥ 0, so the anchor stays where the whole group fits in the room.
public struct RoomPreviewSpan: Equatable, Sendable {
    public var low: Position3D
    public var high: Position3D

    public init(offsets: [Position3D]) {
        var low = Position3D(x: 0, y: 0, z: 0)
        var high = Position3D(x: 0, y: 0, z: 0)
        for offset in offsets {
            low = Position3D(x: min(low.x, offset.x), y: min(low.y, offset.y), z: min(low.z, offset.z))
            high = Position3D(x: max(high.x, offset.x), y: max(high.y, offset.y), z: max(high.z, offset.z))
        }
        self.low = low
        self.high = high
    }

    public static let point = RoomPreviewSpan(offsets: [])
}

/// Domain position that a drag writes back, plus the points that must stay inside the room.
public struct RoomPreviewAnchor: Equatable, Sendable {
    public var position: Position3D
    public var span: RoomPreviewSpan

    public init(position: Position3D, span: RoomPreviewSpan) {
        self.position = position
        self.span = span
    }
}

/// Pure drag math: Apple Y-up cursor movement to a domain position inside the room.
public enum RoomPreviewDrag {
    public static let step = 0.05

    public static func snap(_ value: Double) -> Double {
        (value / step).rounded() * step
    }

    public static func moved(start: Position3D, appleDelta: SIMD3<Float>, roomSize: Position3D, span: RoomPreviewSpan) -> Position3D {
        let proposed = Position3D(
            x: snap(start.x + Double(appleDelta.x)),
            y: snap(start.y - Double(appleDelta.z)),
            z: snap(start.z + Double(appleDelta.y)))
        return clamp(proposed, roomSize: roomSize, span: span)
    }

    public static func clamp(_ point: Position3D, roomSize: Position3D, span: RoomPreviewSpan) -> Position3D {
        Position3D(
            x: axis(point.x, room: roomSize.x, low: span.low.x, high: span.high.x),
            y: axis(point.y, room: roomSize.y, low: span.low.y, high: span.high.y),
            z: axis(point.z, room: roomSize.z, low: span.low.z, high: span.high.z))
    }

    /// Intersection of a view ray with the room's horizontal plane (constant Apple Y, constant domain height).
    /// Returns nil when the ray does not meet that plane in front of the camera.
    public static func hitHorizontalPlane(origin: SIMD3<Float>, direction: SIMD3<Float>, planeY: Float) -> SIMD3<Float>? {
        guard abs(direction.y) > 1e-5 else { return nil }
        let distance = (planeY - origin.y) / direction.y
        guard distance > 0 else { return nil }
        return origin + direction * distance
    }

    public static func appleShift(from start: Position3D, to end: Position3D) -> SIMD3<Float> {
        let apple = CoordinateTransform.toApple(Position3D(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z))
        return SIMD3(Float(apple.x), Float(apple.y), Float(apple.z))
    }

    private static func axis(_ value: Double, room: Double, low: Double, high: Double) -> Double {
        let lower = -low
        let upper = room - high
        if upper < lower { return lower }
        return min(max(value, lower), upper)
    }
}
