import Foundation
import SimuCore

/// Deterministic broad phase only. Final closed slab/tie semantics are unchanged.
public struct PreviewCollisionIndex: Sendable {
    private struct Node: Sendable {
        let bounds: GeometryBounds
        let children: [Int]
        let obstacles: [PreviewObstacle]
    }
    private let nodes: [Node]
    public init(obstacles: [PreviewObstacle]) {
        var nodes: [Node] = []
        func build(_ values: [PreviewObstacle]) -> Int {
            let lower = PreviewVector(values[0].bounds.origin)
            var lo = lower
            var hi = lower + PreviewVector(values[0].bounds.size)
            for value in values.dropFirst() {
                let a = PreviewVector(value.bounds.origin)
                let b = a + PreviewVector(value.bounds.size)
                lo = .init(min(lo.x, a.x), min(lo.y, a.y), min(lo.z, a.z))
                hi = .init(max(hi.x, b.x), max(hi.y, b.y), max(hi.z, b.z))
            }
            let bounds = GeometryBounds(origin: lo.position, size: (hi - lo).position)
            let index = nodes.count
            nodes.append(.init(bounds: bounds, children: [], obstacles: []))
            if values.count <= 4 {
                nodes[index] = .init(bounds: bounds, children: [], obstacles: values)
                return index
            }
            let extent = hi - lo
            let axis = extent.x >= extent.y && extent.x >= extent.z ? 0 : extent.y >= extent.z ? 1 : 2
            let sorted = values.sorted {
                let a = PreviewVector($0.bounds.origin)[axis] + PreviewVector($0.bounds.size)[axis] / 2
                let b = PreviewVector($1.bounds.origin)[axis] + PreviewVector($1.bounds.size)[axis] / 2
                return a == b ? $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() : a < b
            }
            let middle = sorted.count / 2
            let left = build(Array(sorted.prefix(middle)))
            let right = build(Array(sorted.dropFirst(middle)))
            nodes[index] = .init(bounds: bounds, children: [left, right], obstacles: [])
            return index
        }
        if !obstacles.isEmpty { _ = build(obstacles) }
        self.nodes = nodes
    }
    public func firstObstacle(from: Position3D, to: Position3D, tolerance: Double) -> PreviewSegmentHit? {
        guard !nodes.isEmpty else { return nil }
        var stack = [0]
        var candidates: [PreviewObstacle] = []
        while let index = stack.popLast() {
            let node = nodes[index]
            guard
                SegmentIntersection.slab(from: from, to: to, bounds: node.bounds, tolerance: tolerance) != nil
            else { continue }
            candidates.append(contentsOf: node.obstacles)
            stack.append(contentsOf: node.children)
        }
        return SegmentIntersection.firstObstacle(
            from: from, to: to, obstacles: candidates, tolerance: tolerance)
    }
}
