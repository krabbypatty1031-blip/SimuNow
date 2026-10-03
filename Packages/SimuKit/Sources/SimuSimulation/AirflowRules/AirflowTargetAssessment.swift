import Foundation
import SimuCore

public enum AirflowTargetAssessment {
    public static func assess(_ input: AirflowPreviewInput) throws -> [PreviewTargetRelation] {
        var relations: [PreviewTargetRelation] = []
        for seat in input.seats {
            let targets: [(UUID?, Position3D, Bool)] =
                seat.samples.isEmpty
                ? [(nil, seat.position, true)] : seat.samples.map { ($0.id, $0.position, false) }
            for (sampleID, point, marker) in targets {
                try Task.checkCancellation()
                let state: PreviewRelationState
                let hit: PreviewSegmentHit?
                let reason: AnalysisMissingReason?
                let rule: String
                if seat.roomID != input.roomID || !PreviewVector(point).finite || !input.isFluid(point) {
                    state = .notEvaluated
                    hit = nil
                    reason = .init(
                        code: "target_not_in_fluid",
                        fieldPath: "/seats/\(seat.id)/samples/\(sampleID?.uuidString ?? "position")",
                        reason: "点位不属于可评价流体域；不按零或范围外统计。")
                    rule = "preview.unsupported.v1"
                } else if input.field.sample(at: point) == nil {
                    state = .outsideAssumedPath
                    hit = nil
                    reason = nil
                    rule = "preview.pathIntersection.v1"
                } else if let blocked = input.collisionIndex.firstObstacle(
                    from: input.field.origin, to: point,
                    tolerance: input.field.profile.geometryToleranceMeters)
                {
                    state = .occluded
                    hit = blocked
                    reason = nil
                    rule = "preview.occlusion.v1"
                } else {
                    state = .intersectsAssumedPath
                    hit = nil
                    reason = nil
                    rule = "preview.pathIntersection.v1"
                }
                relations.append(
                    .init(
                        seatID: seat.id, sampleID: sampleID, position: point, isPositionMarker: marker,
                        state: state, hitEntityID: hit?.obstacleID, missingReason: reason, ruleID: rule,
                        hitPosition: hit?.position))
            }
        }
        return relations
    }
}
public struct PreviewRelationCounts: Equatable, Sendable {
    public let intersects: Int
    public let occluded: Int
    public let outside: Int
    public let notEvaluated: Int
    public init(_ relations: [PreviewTargetRelation]) {
        intersects = relations.filter { $0.state == .intersectsAssumedPath }.count
        occluded = relations.filter { $0.state == .occluded }.count
        outside = relations.filter { $0.state == .outsideAssumedPath }.count
        notEvaluated = relations.filter { $0.state == .notEvaluated }.count
    }
    public var isMixed: Bool { [intersects, occluded, outside, notEvaluated].filter { $0 > 0 }.count > 1 }
}
public struct PreviewSeatAssessment: Equatable, Sendable {
    public let seatID: UUID
    public let relations: [PreviewTargetRelation]
    public let counts: PreviewRelationCounts
    public init(seatID: UUID, relations: [PreviewTargetRelation]) {
        self.seatID = seatID
        self.relations = relations
        counts = .init(relations)
    }
    public static func grouped(_ payload: AirflowPreviewPayload) -> [Self] {
        let IDs = payload.relations.map(\.seatID).reduce(into: [UUID]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return IDs.map { id in .init(seatID: id, relations: payload.relations.filter { $0.seatID == id }) }
    }
}
