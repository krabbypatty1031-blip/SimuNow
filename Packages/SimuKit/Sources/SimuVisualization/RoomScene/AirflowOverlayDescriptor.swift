import Foundation
import SimuCore

public struct AirflowOverlayDescriptor: Equatable, Sendable {
    public let identity: RunIdentity
    public let profileID: String
    public let profileVersion: Int
    public let scene: RoomSceneOverlay
    public init(result: LocalAnalysisResult) throws {
        guard result.method == .init(kind: .airflowPreview), result.basis == .rulePreview,
            result.checks.state == .passed,
            case .airflowPreview(let payload) = result.payload
        else { throw ProjectDataError.contract("No checked rule preview") }
        identity = result.identity
        profileID = payload.profileID
        profileVersion = payload.profileVersion
        scene = .init(
            paths: payload.paths.filter { $0.points.count >= 2 }.map {
                .init(
                    id: "\(result.identity.runID.uuidString.lowercased())/\($0.id)",
                    points: $0.points.map(\.position), blocked: $0.termination == .hit, hitEntityID: $0.hitEntityID)
            },
            explanation: "几何规则预览 · \(payload.profileID) v\(payload.profileVersion) · 展示强度单位 1；不表示现实风速、温度或舒适。")
        if let error = scene.validationMessage { throw ProjectDataError.contract(error) }
    }
}
