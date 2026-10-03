import Foundation
import SimuCore

public struct SurfaceRectangle: Equatable, Sendable {
    public let u: Double
    public let v: Double
    public let width: Double
    public let height: Double
    public init(u: Double, v: Double, width: Double, height: Double) { self.u = u; self.v = v; self.width = width; self.height = height }
    public func contains(u: Double, v: Double) -> Bool { u > self.u && u < self.u + width && v > self.v && v < self.v + height }
}
public enum OpeningGeometryError: Error, Equatable, Sendable { case invalidDimensions, tooManyCells }
public enum OpeningGeometry {
    public static func normal(_ face: SurfaceFace) -> Direction3D {
        switch face {
        case .xMin: .init(x: -1, y: 0, z: 0)
        case .xMax: .init(x: 1, y: 0, z: 0)
        case .yMin: .init(x: 0, y: -1, z: 0)
        case .yMax: .init(x: 0, y: 1, z: 0)
        case .floor: .init(x: 0, y: 0, z: -1)
        case .ceiling: .init(x: 0, y: 0, z: 1)
        }
    }
    public static func extent(_ face: SurfaceFace, bounds: GeometryBounds) -> (u: Double, v: Double) {
        switch face {
        case .xMin, .xMax: (bounds.size.y, bounds.size.z)
        case .yMin, .yMax: (bounds.size.x, bounds.size.z)
        case .floor, .ceiling: (bounds.size.x, bounds.size.y)
        }
    }
    public static func point(_ face: SurfaceFace, u: Double, v: Double, bounds: GeometryBounds) -> Position3D {
        let o = bounds.origin, s = bounds.size
        switch face {
        case .xMin: return .init(x: o.x, y: o.y + u, z: o.z + v)
        case .xMax: return .init(x: o.x + s.x, y: o.y + u, z: o.z + v)
        case .yMin: return .init(x: o.x + u, y: o.y, z: o.z + v)
        case .yMax: return .init(x: o.x + u, y: o.y + s.y, z: o.z + v)
        case .floor: return .init(x: o.x + u, y: o.y + v, z: o.z)
        case .ceiling: return .init(x: o.x + u, y: o.y + v, z: o.z + s.z)
        }
    }
    /// Counter-clockwise when seen from outside. The coordinate transform preserves handedness.
    public static func quad(_ face: SurfaceFace, rectangle: SurfaceRectangle, bounds: GeometryBounds) -> [Position3D] {
        let r = rectangle
        let values = [(r.u,r.v), (r.u+r.width,r.v), (r.u+r.width,r.v+r.height), (r.u,r.v+r.height)]
        let reverse = [.xMin, .yMax, .floor].contains(face)
        return (reverse ? values.reversed().map { $0 } : values).map { point(face, u: $0.0, v: $0.1, bounds: bounds) }
    }
    public static func rectangle(_ opening: Opening, face: SurfaceFace, bounds: GeometryBounds) -> SurfaceRectangle? {
        guard let u = opening.offsetU.value, let v = opening.offsetV.value,
              let w = opening.width.value, let h = opening.height.value,
              [u,v,w,h].allSatisfy(\.isFinite), u >= 0, v >= 0, w > 0, h > 0 else { return nil }
        let e = extent(face, bounds: bounds)
        guard u+w <= e.u, v+h <= e.v else { return nil }
        return .init(u: u, v: v, width: w, height: h)
    }
    /// Exact union subtraction by a deterministic UV grid. No wall cell covers an opening.
    public static func wallCells(face: SurfaceFace, bounds: GeometryBounds, openings: [SurfaceRectangle], maximumCells: Int = 4096) throws -> [SurfaceRectangle] {
        let e = extent(face, bounds: bounds)
        guard [e.u,e.v].allSatisfy({ $0.isFinite && $0 > 0 }), maximumCells > 0,
              openings.allSatisfy({ [$0.u,$0.v,$0.width,$0.height].allSatisfy(\.isFinite) && $0.u >= 0 && $0.v >= 0 && $0.width > 0 && $0.height > 0 && $0.u+$0.width <= e.u && $0.v+$0.height <= e.v }) else { throw OpeningGeometryError.invalidDimensions }
        let us = Array(Set([0,e.u] + openings.flatMap { [$0.u,$0.u+$0.width] })).sorted()
        let vs = Array(Set([0,e.v] + openings.flatMap { [$0.v,$0.v+$0.height] })).sorted()
        guard us.count-1 <= maximumCells / (vs.count-1) else { throw OpeningGeometryError.tooManyCells }
        var result: [SurfaceRectangle] = []
        for u in 0..<(us.count-1) { for v in 0..<(vs.count-1) {
            if openings.contains(where: { $0.contains(u: (us[u]+us[u+1])/2, v: (vs[v]+vs[v+1])/2) }) { continue }
            result.append(.init(u: us[u], v: vs[v], width: us[u+1]-us[u], height: vs[v+1]-vs[v]))
        } }
        return result
    }
    /// Center/pivot and positive box dimensions. Display thickness extends only outwards.
    public static func wallBox(face: SurfaceFace, rectangle: SurfaceRectangle, bounds: GeometryBounds, thickness: Double = 0.02) -> (center: Position3D, size: Position3D) {
        let r = rectangle, n = normal(face)
        let p = point(face, u: r.u+r.width/2, v: r.v+r.height/2, bounds: bounds)
        let center = Position3D(x: p.x+n.x*thickness/2, y: p.y+n.y*thickness/2, z: p.z+n.z*thickness/2)
        let size: Position3D
        switch face {
        case .xMin, .xMax: size = .init(x: thickness, y: r.width, z: r.height)
        case .yMin, .yMax: size = .init(x: r.width, y: thickness, z: r.height)
        case .floor, .ceiling: size = .init(x: r.width, y: r.height, z: thickness)
        }
        return (center,size)
    }
}
