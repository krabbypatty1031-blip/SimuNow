import Foundation
import SimuCore

public enum AirflowPreviewError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedProfile
    case invalidInput(String)
    case noValidEmission
    public var errorDescription: String? {
        switch self {
        case .unsupportedProfile: "该展示档案或版本尚未支持。"
        case .invalidInput(let message): message
        case .noValidEmission: "所有截面发射点都位于域外或家具内，没有有效预览；请修正风口与家具位置。"
        }
    }
}
public struct PreviewVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
    public init(_ p: Position3D) { self.init(p.x, p.y, p.z) }
    public init(_ d: Direction3D) { self.init(d.x, d.y, d.z) }
    public var position: Position3D { .init(x: x, y: y, z: z) }
    public var direction: Direction3D { .init(x: x, y: y, z: z) }
    public var norm: Double { sqrt(dot(self)) }
    public var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public func dot(_ b: Self) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: Self) -> Self { .init(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    public func unit() -> Self { self / norm }
    public subscript(_ i: Int) -> Double { i == 0 ? x : i == 1 ? y : z }
    public static func + (a: Self, b: Self) -> Self { .init(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Self, b: Self) -> Self { .init(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Self, b: Double) -> Self { .init(a.x * b, a.y * b, a.z * b) }
    public static func / (a: Self, b: Double) -> Self { a * (1 / b) }
}
public struct PreviewProfile: Equatable, Sendable {
    public let configuration: AirflowPreviewConfiguration
    public let lengthMeters: Double
    public let geometryToleranceMeters: Double
    public let wallSourceOffsetMeters: Double
    public var slope: Double { tan(configuration.halfAngleDegrees * .pi / 180) }
    public init(configuration: AirflowPreviewConfiguration, room: GeometryBounds) throws {
        guard configuration.profileID == "simunow.preview.genericCone", configuration.profileVersion == 1
        else { throw AirflowPreviewError.unsupportedProfile }
        let diagonal = PreviewVector(room.size).norm
        guard diagonal.isFinite, diagonal > 0, configuration.baseRadiusMeters.isFinite,
            configuration.baseRadiusMeters > 0,
            configuration.halfAngleDegrees.isFinite, (1...45).contains(configuration.halfAngleDegrees),
            (1...64).contains(configuration.pathCount), (1...128).contains(configuration.maximumSegments),
            configuration.minimumStrength.isFinite, (0...1).contains(configuration.minimumStrength),
            configuration.source.kind == .assumed,
            configuration.source.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { throw AirflowPreviewError.invalidInput("Invalid or unlabelled display profile") }
        let length = configuration.lengthMeters ?? diagonal
        guard length.isFinite, length > 0, length <= diagonal else {
            throw AirflowPreviewError.invalidInput("Preview length must not exceed the room diagonal")
        }
        self.configuration = configuration
        lengthMeters = length
        geometryToleranceMeters = min(1e-8, max(1e-10, diagonal * 1e-10))
        wallSourceOffsetMeters = min(1e-4, max(1e-6, diagonal * 1e-7))
    }
}
public struct RuleFieldSample: Equatable, Sendable {
    public let direction: Direction3D
    public let pathStrength: Double
}
public struct RuleDirectionField: Equatable, Sendable {
    public let origin: Position3D
    public let axis: Direction3D
    public let profile: PreviewProfile
    public let e1: Direction3D
    public let e2: Direction3D
    public init(origin: Position3D, direction: Direction3D, profile: PreviewProfile) throws {
        let d = PreviewVector(direction)
        guard PreviewVector(origin).finite, d.finite, abs(d.norm - 1) <= 1e-6 else {
            throw AirflowPreviewError.invalidInput("Direction must be a finite unit vector")
        }
        let unit = d.unit()
        let helpers = [PreviewVector(1, 0, 0), PreviewVector(0, 1, 0), PreviewVector(0, 0, 1)]
        var helper = helpers[0]
        for candidate in helpers.dropFirst() where abs(unit.dot(candidate)) < abs(unit.dot(helper)) {
            helper = candidate
        }
        let first = unit.cross(helper).unit()
        self.origin = origin
        axis = unit.direction
        self.profile = profile
        e1 = first.direction
        e2 = unit.cross(first).direction
    }
    /// Formula only. The caller checks the fluid domain before querying this sample.
    public func sample(at point: Position3D) -> RuleFieldSample? {
        let d = PreviewVector(axis)
        let delta = PreviewVector(point) - PreviewVector(origin)
        let s = delta.dot(d)
        guard delta.finite, s >= 0, s <= profile.lengthMeters else { return nil }
        let radial = delta - d * s
        let width = profile.configuration.baseRadiusMeters + profile.slope * s
        let q = radial.norm / width
        guard q.isFinite, q <= 1 + 1e-12 else { return nil }
        let shaped = d + radial * (profile.slope / width)
        return .init(
            direction: shaped.unit().direction,
            pathStrength: max(0, 1 - q * q) / pow(1 + s / profile.lengthMeters, 2))
    }
}
