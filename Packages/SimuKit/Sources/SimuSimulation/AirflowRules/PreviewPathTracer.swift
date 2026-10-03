import Foundation
import SimuCore

public enum PreviewSampling {
    public static func halton(index: UInt64, base: UInt64) -> Double {
        precondition(base > 1)
        var index = index
        var fraction = 1.0
        var value = 0.0
        while index > 0 {
            fraction /= Double(base)
            value += fraction * Double(index % base)
            index /= base
        }
        return value
    }
}
public struct PreviewPathTrace: Sendable {
    public let paths: [PreviewPath]
    public let rejections: [PreviewEmissionRejection]
}
public enum PreviewPathTracer {
    public static func trace(_ input: AirflowPreviewInput) throws -> PreviewPathTrace {
        let field = input.field
        let profile = field.profile
        let config = profile.configuration
        let d = PreviewVector(field.axis)
        var paths: [PreviewPath] = []
        var rejected: [PreviewEmissionRejection] = []
        for id in 0..<config.pathCount {
            try Task.checkCancellation()
            var start = PreviewVector(field.origin)
            if id > 0 {
                let index = UInt64(id) + UInt64(config.seed)
                let radius = config.baseRadiusMeters * sqrt(PreviewSampling.halton(index: index, base: 2))
                let angle = 2 * Double.pi * PreviewSampling.halton(index: index, base: 3)
                start =
                    start + (PreviewVector(field.e1) * cos(angle) + PreviewVector(field.e2) * sin(angle))
                    * radius
            }
            if input.isWallSource { start = start + d * profile.wallSourceOffsetMeters }
            guard input.isFluid(start.position) else {
                rejected.append(
                    .init(
                        pathID: id,
                        reason: input.room.contains(start.position, tolerance: 0)
                            ? "emission_in_obstacle" : "emission_outside_domain"))
                continue
            }
            var point = start.position
            var points = [
                PreviewPathPoint(position: point, strength: field.sample(at: point)?.pathStrength ?? 0)
            ]
            var termination = PreviewPathTermination.stepLimit
            var hitID: UUID?
            let axialStep = profile.lengthMeters / Double(config.maximumSegments)
            for _ in 0..<config.maximumSegments {
                try Task.checkCancellation()
                let s = (PreviewVector(point) - PreviewVector(field.origin)).dot(d)
                if s >= profile.lengthMeters {
                    termination = .lengthLimit
                    break
                }
                guard let sample = field.sample(at: point), sample.pathStrength >= config.minimumStrength
                else {
                    termination = .weak
                    break
                }
                let direction = PreviewVector(sample.direction)
                let progress = direction.dot(d)
                guard progress.isFinite, progress > 0 else {
                    throw AirflowPreviewError.invalidInput("Rule direction lost forward progress")
                }
                let advance = min(axialStep, profile.lengthMeters - s)
                let next = (PreviewVector(point) + direction * (advance / progress)).position
                if let hit = SegmentIntersection.firstHit(from: point, to: next, input: input) {
                    points.append(
                        .init(
                            position: hit.position,
                            strength: field.sample(at: hit.position)?.pathStrength ?? 0))
                    termination = hit.obstacleID == nil ? .escaped : .hit
                    hitID = hit.obstacleID
                    break
                }
                point = next
                points.append(.init(position: point, strength: field.sample(at: point)?.pathStrength ?? 0))
                if advance < axialStep || s + advance >= profile.lengthMeters {
                    termination = .lengthLimit
                    break
                }
            }
            paths.append(.init(id: id, points: points, termination: termination, hitEntityID: hitID))
        }
        guard !paths.isEmpty else { throw AirflowPreviewError.noValidEmission }
        return .init(paths: paths, rejections: rejected)
    }
}
