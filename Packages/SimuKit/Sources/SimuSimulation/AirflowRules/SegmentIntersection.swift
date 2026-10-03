import Foundation
import SimuCore

public struct PreviewSegmentHit: Equatable, Sendable {
    public let t: Double
    public let position: Position3D
    public let obstacleID: UUID?
}
public enum SegmentIntersection {
    /// Closed slabs, including tangent/corner contacts. Parallel axes never divide by zero.
    public static func slab(from: Position3D, to: Position3D, bounds: GeometryBounds, tolerance: Double) -> (
        enter: Double, exit: Double
    )? {
        let a = PreviewVector(from)
        let delta = PreviewVector(to) - a
        let lo = PreviewVector(bounds.origin)
        let hi = lo + PreviewVector(bounds.size)
        guard a.finite, delta.finite, tolerance.isFinite, tolerance >= 0 else { return nil }
        var enter = 0.0
        var exit = 1.0
        for i in 0..<3 {
            if delta[i] == 0 {
                if a[i] < lo[i] - tolerance || a[i] > hi[i] + tolerance { return nil }
                continue
            }
            let first = (lo[i] - a[i]) / delta[i]
            let last = (hi[i] - a[i]) / delta[i]
            enter = max(enter, min(first, last))
            exit = min(exit, max(first, last))
            // Parameter tolerance is scaled from metres; no expanded physical box is used.
            if enter > exit + tolerance / max(delta.norm, 1e-12) { return nil }
        }
        guard exit >= 0, enter <= 1 else { return nil }
        return (min(1, max(0, enter)), min(1, max(0, exit)))
    }
    public static func firstObstacle(
        from: Position3D, to: Position3D, obstacles: [PreviewObstacle], tolerance: Double
    ) -> PreviewSegmentHit? {
        let delta = PreviewVector(to) - PreviewVector(from)
        let tTolerance = tolerance / max(delta.norm, 1e-12)
        var hits: [PreviewSegmentHit] = []
        for obstacle in obstacles {
            guard let interval = slab(from: from, to: to, bounds: obstacle.bounds, tolerance: tolerance)
            else { continue }
            hits.append(
                .init(
                    t: interval.enter, position: (PreviewVector(from) + delta * interval.enter).position,
                    obstacleID: obstacle.id))
        }
        guard let minimum = hits.map(\.t).min() else { return nil }
        // A fixed tie set around the global earliest hit, never a pairwise tolerance chain.
        return hits.filter { $0.t <= minimum + tTolerance }.min {
            $0.obstacleID!.uuidString.lowercased() < $1.obstacleID!.uuidString.lowercased()
        }
    }
    public static func firstHit(from: Position3D, to: Position3D, input: AirflowPreviewInput)
        -> PreviewSegmentHit?
    {
        let tolerance = input.field.profile.geometryToleranceMeters
        let obstacle = input.collisionIndex.firstObstacle(from: from, to: to, tolerance: tolerance)
        let destination = PreviewVector(to)
        let delta = destination - PreviewVector(from)
        let lower = PreviewVector(input.room.origin)
        let upper = lower + PreviewVector(input.room.size)
        let touchesExit = (0..<3).contains { axis in
            (delta[axis] < 0 && abs(destination[axis] - lower[axis]) <= tolerance)
                || (delta[axis] > 0 && abs(destination[axis] - upper[axis]) <= tolerance)
        }
        guard !input.room.contains(to, tolerance: 0) || touchesExit,
            let slab = slab(from: from, to: to, bounds: input.room, tolerance: tolerance)
        else { return obstacle }
        let t = slab.exit
        if let obstacle,
            obstacle.t <= t + tolerance / max((PreviewVector(to) - PreviewVector(from)).norm, 1e-12)
        {
            return obstacle
        }
        return .init(
            t: t, position: (PreviewVector(from) + (PreviewVector(to) - PreviewVector(from)) * t).position,
            obstacleID: nil)
    }
}
