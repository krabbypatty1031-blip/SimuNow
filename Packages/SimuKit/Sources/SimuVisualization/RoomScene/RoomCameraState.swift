import Foundation
import SimuCore

/// Transient display state, intentionally not Codable and never part of a project or analysis input.
public struct RoomCameraState: Equatable, Sendable {
    public private(set) var target: Position3D
    public private(set) var distance: Double
    public private(set) var yawDegrees: Double
    public private(set) var pitchDegrees: Double
    public let fieldOfViewDegrees: Double
    public init(target: Position3D, distance: Double, yawDegrees: Double = 45, pitchDegrees: Double = 35, fieldOfViewDegrees: Double = 45) {
        self.target = target
        self.distance = distance.isFinite && distance > 0 ? distance : 1
        self.yawDegrees = yawDegrees.isFinite ? yawDegrees.truncatingRemainder(dividingBy: 360) : 45
        self.pitchDegrees = pitchDegrees.isFinite ? min(89,max(-85,pitchDegrees)) : 35
        self.fieldOfViewDegrees = fieldOfViewDegrees.isFinite ? min(120,max(10,fieldOfViewDegrees)) : 45
    }
    public var position: Position3D {
        let yaw = yawDegrees * .pi/180, pitch = pitchDegrees * .pi/180
        return .init(x: target.x+distance*cos(pitch)*cos(yaw), y: target.y+distance*cos(pitch)*sin(yaw), z: target.z+distance*sin(pitch))
    }
    public static func fitting(bounds: GeometryBounds, aspectRatio: Double, yawDegrees: Double = 45, pitchDegrees: Double = 35) -> Self {
        let diagonal = diagonal(bounds), aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        let vertical = 45.0 * .pi/360, horizontal = atan(tan(vertical)*aspect)
        let desired = diagonal/2 / sin(min(vertical,horizontal)) * 1.1
        return .init(target: RoomSceneBuilder.center(bounds), distance: min(diagonal*5,max(diagonal*0.25,desired)), yawDegrees: yawDegrees, pitchDegrees: pitchDegrees)
    }
    public mutating func reset(bounds: GeometryBounds, aspectRatio: Double) { self = .fitting(bounds: bounds, aspectRatio: aspectRatio) }
    public mutating func top(bounds: GeometryBounds, aspectRatio: Double) { self = .fitting(bounds: bounds, aspectRatio: aspectRatio, yawDegrees: -90, pitchDegrees: 89) }
    public mutating func focus(_ bounds: GeometryBounds, roomBounds: GeometryBounds, aspectRatio: Double) {
        let fitted = Self.fitting(bounds: bounds, aspectRatio: aspectRatio, yawDegrees: yawDegrees, pitchDegrees: pitchDegrees)
        target = fitted.target; distance = fitted.distance
        constrain(roomBounds)
    }
    public mutating func orbit(horizontalDegrees: Double, verticalDegrees: Double) {
        guard horizontalDegrees.isFinite, verticalDegrees.isFinite else { return }
        yawDegrees = (yawDegrees+horizontalDegrees).truncatingRemainder(dividingBy: 360)
        pitchDegrees = min(89,max(-85,pitchDegrees+verticalDegrees))
    }
    public mutating func zoom(factor: Double, roomBounds: GeometryBounds) {
        guard factor.isFinite, factor > 0 else { return }
        distance *= factor; constrain(roomBounds)
    }
    /// Screen-relative pan is a display transform, never a model edit.
    public mutating func pan(horizontal: Double, vertical: Double, roomBounds: GeometryBounds) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        let r = right, u = up, margin = Self.diagonal(roomBounds)
        let dx = (r.x * horizontal + u.x * vertical) * distance
        let dy = (r.y * horizontal + u.y * vertical) * distance
        let dz = (r.z * horizontal + u.z * vertical) * distance
        target = .init(x: min(roomBounds.origin.x + roomBounds.size.x + margin, max(roomBounds.origin.x - margin, target.x + dx)),
                       y: min(roomBounds.origin.y + roomBounds.size.y + margin, max(roomBounds.origin.y - margin, target.y + dy)),
                       z: min(roomBounds.origin.z + roomBounds.size.z + margin, max(roomBounds.origin.z - margin, target.z + dz)))
    }
    private mutating func constrain(_ bounds: GeometryBounds) { let d = Self.diagonal(bounds); distance = min(d*5,max(d*0.25,distance)) }
    public static func diagonal(_ bounds: GeometryBounds) -> Double { sqrt(bounds.size.x*bounds.size.x + bounds.size.y*bounds.size.y + bounds.size.z*bounds.size.z) }
    public var forward: Direction3D { RoomVector.normalized(.init(x: target.x-position.x, y: target.y-position.y, z: target.z-position.z)) }
    public var right: Direction3D { RoomVector.normalized(RoomVector.cross(forward,.init(x: 0,y: 0,z: 1))) }
    public var up: Direction3D { RoomVector.cross(right,forward) }
    public func ray(x: Double, y: Double, viewportWidth: Double, viewportHeight: Double) -> RoomPickingRay? {
        guard [x,y,viewportWidth,viewportHeight].allSatisfy(\.isFinite), viewportWidth > 0, viewportHeight > 0 else { return nil }
        let v = tan(fieldOfViewDegrees * .pi/360), h = v*viewportWidth/viewportHeight
        let nx = (2*x/viewportWidth-1)*h, ny = (1-2*y/viewportHeight)*v
        let f = forward, r = right, u = up
        let direction = RoomVector.normalized(.init(x: f.x+r.x*nx+u.x*ny, y: f.y+r.y*nx+u.y*ny, z: f.z+r.z*nx+u.z*ny))
        return .init(origin: position, direction: direction)
    }
}
public struct RoomSceneVisibility: Equatable, Sendable {
    public var showCeiling: Bool
    public var hideFacingWalls: Bool
    public init(showCeiling: Bool = false, hideFacingWalls: Bool = true) { self.showCeiling = showCeiling; self.hideFacingWalls = hideFacingWalls }
    public func isVisible(_ node: RoomSceneNode, camera: RoomCameraState) -> Bool {
        guard let face = node.face else { return true }
        if face == .ceiling && !showCeiling { return false }
        guard hideFacingWalls else { return true }
        let p = camera.position, t = camera.target
        return !((face == .xMax && p.x >= t.x) || (face == .xMin && p.x < t.x) || (face == .yMax && p.y >= t.y) || (face == .yMin && p.y < t.y))
    }
}
struct RoomVector {
    static func dot(_ a: Direction3D, _ b: Direction3D) -> Double { a.x*b.x+a.y*b.y+a.z*b.z }
    static func cross(_ a: Direction3D, _ b: Direction3D) -> Direction3D { .init(x: a.y*b.z-a.z*b.y, y: a.z*b.x-a.x*b.z, z: a.x*b.y-a.y*b.x) }
    static func normalized(_ value: Direction3D) -> Direction3D {
        let n = sqrt(dot(value,value)); guard n.isFinite, n > 1e-15 else { return .init(x: 0,y: 0,z: -1) }
        return .init(x: value.x/n, y: value.y/n, z: value.z/n)
    }
}
