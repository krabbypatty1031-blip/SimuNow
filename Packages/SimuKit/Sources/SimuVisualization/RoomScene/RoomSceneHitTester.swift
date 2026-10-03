import Foundation
import SimuCore

public struct RoomPickingRay: Equatable, Sendable {
    public let origin: Position3D
    public let direction: Direction3D
    public init(origin: Position3D, direction: Direction3D) { self.origin = origin; self.direction = direction }
}
public struct RoomSceneHit: Equatable, Sendable {
    public let key: SceneObjectKey
    public let distance: Double
}
/// Display picking only. These approximations are never used for airflow or geometry validation.
public enum RoomSceneHitTester {
    public static func hit(ray: RoomPickingRay, descriptor: SceneDescriptor, camera: RoomCameraState, visibility: RoomSceneVisibility) -> RoomSceneHit? {
        var nearest: RoomSceneHit?
        for node in descriptor.nodes where node.selectable && visibility.isVisible(node,camera: camera) {
            guard let distance = distance(ray: ray, node: node), distance >= 0,
                  nearest == nil || distance < nearest!.distance else { continue }
            nearest = .init(key: node.key.object, distance: distance)
        }
        return nearest
    }
    public static func distance(ray: RoomPickingRay, node: RoomSceneNode) -> Double? {
        switch node.geometry {
        case .box(let size): return box(ray, .init(origin: .init(x: node.position.x-size.x/2, y: node.position.y-size.y/2, z: node.position.z-size.z/2), size: size))
        case .sphere(let radius): return sphere(ray,node.position,radius)
        case .segment(let v, let radius): return capsule(ray,node.position,.init(x: v.x,y: v.y,z: v.z),radius)
        case .arrow(let direction, let length, let radius): return capsule(ray,node.position,.init(x: direction.x*length,y: direction.y*length,z: direction.z*length),radius*3)
        }
    }
    private static func box(_ ray: RoomPickingRay, _ bounds: GeometryBounds) -> Double? {
        var near = 0.0, far = Double.infinity
        for (o,d,lo,size) in [(ray.origin.x,ray.direction.x,bounds.origin.x,bounds.size.x), (ray.origin.y,ray.direction.y,bounds.origin.y,bounds.size.y), (ray.origin.z,ray.direction.z,bounds.origin.z,bounds.size.z)] {
            if abs(d) <= 1e-15 { if o < lo || o > lo+size { return nil }; continue }
            let a = (lo-o)/d, b = (lo+size-o)/d
            near = max(near,min(a,b)); far = min(far,max(a,b)); if far < near { return nil }
        }
        return near.isFinite ? near : nil
    }
    private static func sphere(_ ray: RoomPickingRay, _ center: Position3D, _ radius: Double) -> Double? {
        let oc = Direction3D(x: ray.origin.x-center.x,y: ray.origin.y-center.y,z: ray.origin.z-center.z)
        let b = RoomVector.dot(oc,ray.direction), c = RoomVector.dot(oc,oc)-radius*radius
        let discriminant = b*b-c
        guard discriminant >= 0 else { return nil }
        let near = -b-sqrt(discriminant), far = -b+sqrt(discriminant)
        return near >= 0 ? near : far >= 0 ? 0 : nil
    }
    private static func capsule(_ ray: RoomPickingRay, _ start: Position3D, _ vector: Direction3D, _ radius: Double) -> Double? {
        let length = sqrt(RoomVector.dot(vector,vector))
        if length < 1e-12 { return sphere(ray,start,radius) }
        let axis = RoomVector.normalized(vector)
        let delta = Direction3D(x: ray.origin.x-start.x,y: ray.origin.y-start.y,z: ray.origin.z-start.z)
        let ad = RoomVector.dot(axis,ray.direction), ao = RoomVector.dot(axis,delta)
        let a = 1-ad*ad, b = RoomVector.dot(delta,ray.direction)-ao*ad, c = RoomVector.dot(delta,delta)-ao*ao-radius*radius
        var hits: [Double] = []
        if a > 1e-12, b*b-a*c >= 0 {
            let root = sqrt(b*b-a*c)
            for t in [(-b-root)/a,(-b+root)/a] where t >= 0 {
                let along = ao+t*ad
                if (0...length).contains(along) { hits.append(t) }
            }
        }
        if let t = sphere(ray,start,radius) { hits.append(t) }
        if let t = sphere(ray,.init(x: start.x+vector.x,y: start.y+vector.y,z: start.z+vector.z),radius) { hits.append(t) }
        return hits.min()
    }
}
