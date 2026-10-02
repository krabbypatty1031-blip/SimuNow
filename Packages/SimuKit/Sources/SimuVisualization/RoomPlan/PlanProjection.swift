import Foundation
import SimuCore

public struct PlanPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Fits a metre-based, Z-up room into a screen. Screen Y is inverted in this one place.
public struct PlanProjection: Equatable, Sendable {
    public let bounds: GeometryBounds
    public let scale: Double
    public let offset: PlanPoint
    public init?(bounds: GeometryBounds, screenWidth: Double, screenHeight: Double, padding: Double = 24) {
        guard [bounds.origin.x, bounds.origin.y, bounds.size.x, bounds.size.y, screenWidth, screenHeight, padding].allSatisfy(\.isFinite),
              bounds.size.x > 0, bounds.size.y > 0, padding >= 0,
              screenWidth > padding * 2, screenHeight > padding * 2 else { return nil }
        self.bounds = bounds
        scale = min((screenWidth - padding * 2) / bounds.size.x, (screenHeight - padding * 2) / bounds.size.y)
        offset = .init(x: (screenWidth - bounds.size.x * scale) / 2, y: (screenHeight - bounds.size.y * scale) / 2)
    }
    public func project(_ position: Position3D) -> PlanPoint {
        .init(x: offset.x + (position.x - bounds.origin.x) * scale,
              y: offset.y + (bounds.origin.y + bounds.size.y - position.y) * scale)
    }
    public func unproject(_ point: PlanPoint, z: Double) -> Position3D {
        .init(x: bounds.origin.x + (point.x - offset.x) / scale,
              y: bounds.origin.y + bounds.size.y - (point.y - offset.y) / scale, z: z)
    }
    public func contains(_ point: PlanPoint) -> Bool {
        point.x >= offset.x && point.x <= offset.x + bounds.size.x * scale &&
        point.y >= offset.y && point.y <= offset.y + bounds.size.y * scale
    }
}

/// Yaw: +X toward +Y; pitch: horizontal toward +Z. Both are in degrees.
public enum AirflowDirection {
    public static func unit(yawDegrees: Double, pitchDegrees: Double) throws -> Direction3D {
        guard yawDegrees.isFinite, pitchDegrees.isFinite, (-90...90).contains(pitchDegrees) else {
            throw ProjectDataError.contract("风向角必须为有限数；俯仰角应在 −90° 至 90° 之间。")
        }
        let yaw = yawDegrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        let pitch = pitchDegrees * .pi / 180
        return .init(x: cos(pitch) * cos(yaw), y: cos(pitch) * sin(yaw), z: sin(pitch))
    }
    public static func angles(_ direction: Direction3D) -> (yaw: Double, pitch: Double) {
        let horizontal = hypot(direction.x, direction.y)
        var yaw = atan2(direction.y, direction.x) * 180 / .pi
        if yaw < 0 { yaw += 360 }
        return (yaw, atan2(direction.z, horizontal) * 180 / .pi)
    }
}

public enum RoomPlanObjectKind: String, Hashable, Sendable {
    case furniture, seat, sample, equipment, hvac, port, control
    public var title: String {
        switch self {
        case .furniture: "家具"
        case .seat: "座位"
        case .sample: "采样点"
        case .equipment: "设备热源"
        case .hvac: "空调"
        case .port: "风口"
        case .control: "温控测点"
        }
    }
}
public struct RoomPlanSelection: Hashable, Sendable, Identifiable {
    public let kind: RoomPlanObjectKind
    public let objectID: UUID
    public var id: String { kind.rawValue + ":" + objectID.uuidString }
    public init(kind: RoomPlanObjectKind, objectID: UUID) { self.kind = kind; self.objectID = objectID }
}
