import Foundation
import SimuCore
import SimuSimulation

public enum PreviewConfigurationEditingError: Error, LocalizedError, Sendable, Equatable {
    case staleDraft
    case invalidNumber(String)
    public var errorDescription: String? {
        switch self {
        case .staleDraft: "项目、方案或档案已改变；请关闭并重新打开展示档案。"
        case .invalidNumber(let field): "\(field) 需填写支持范围内的有效数值。"
        }
    }
}
/// Frozen input/config baseline. Native run attachments are deliberately not part of this editor transaction.
public struct AirflowPreviewConfigurationDraft: Identifiable, Sendable {
    public let id = UUID()
    public let project: ProjectDocument
    public let scenarioID: UUID
    public let store: AnalysisConfigurationStore?
    public let original: AnalysisConfiguration?
    public var radiusText: String
    public var angleText: String
    public var seedText: String
    public var pathCount: Int
    public init(project: ProjectDocument, scenarioID: UUID, store: AnalysisConfigurationStore?) {
        self.project = project
        self.scenarioID = scenarioID
        self.store = store
        original = store?.configuration(scenarioID: scenarioID, kind: .airflowPreview)
        let profile: AirflowPreviewConfiguration
        if case .airflowPreview(let value) = original?.payload { profile = value } else { profile = .init() }
        radiusText = String(profile.baseRadiusMeters)
        angleText = String(profile.halfAngleDegrees)
        seedText = String(profile.seed)
        pathCount = profile.pathCount
    }
    public func applying(
        currentProject: ProjectDocument?, currentScenarioID: UUID?, currentStore: AnalysisConfigurationStore?
    ) throws -> AnalysisConfigurationStore {
        guard currentProject == project, currentScenarioID == scenarioID, currentStore == store else {
            throw PreviewConfigurationEditingError.staleDraft
        }
        guard let radius = Double(radiusText.trimmingCharacters(in: .whitespacesAndNewlines)),
            radius.isFinite, radius > 0
        else { throw PreviewConfigurationEditingError.invalidNumber("起始半径") }
        guard let angle = Double(angleText.trimmingCharacters(in: .whitespacesAndNewlines)), angle.isFinite,
            (1...45).contains(angle)
        else { throw PreviewConfigurationEditingError.invalidNumber("扩散半角") }
        guard let seed = UInt32(seedText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PreviewConfigurationEditingError.invalidNumber("seed")
        }
        let profile: AirflowPreviewConfiguration
        if case .airflowPreview(let value) = original?.payload { profile = value } else { profile = .init() }
        let next = AirflowPreviewConfiguration(
            profileID: profile.profileID, profileVersion: profile.profileVersion, baseRadiusMeters: radius,
            halfAngleDegrees: angle, lengthMeters: profile.lengthMeters, pathCount: pathCount,
            maximumSegments: profile.maximumSegments, seed: seed, minimumStrength: profile.minimumStrength,
            source: profile.source)
        var assumptions = original?.acceptedAssumptions ?? []
        if !assumptions.contains(where: { $0.id == next.profileID && $0.version == next.profileVersion }) {
            assumptions.append(
                .init(
                    id: next.profileID, version: next.profileVersion, source: next.source,
                    meaning: "用户明确采用几何展示档案；实际数值保存于配置，不代表实测风速、温度或舒适。"))
        }
        let configuration = AnalysisConfiguration(
            configVersion: original?.configVersion ?? 1,
            roomID: original?.roomID ?? project.geometry.rooms.first?.id,
            deviceID: original?.deviceID
                ?? project.scenarios.first { $0.id == scenarioID }?.inputs.hvac.first?.id,
            payload: .airflowPreview(next), acceptedAssumptions: assumptions,
            resources: original?.resources ?? .standard)
        try NativeAnalysisCodec().validateConfiguration(configuration)
        var nextStore = store ?? .init(projectID: project.id)
        nextStore.set(configuration, scenarioID: scenarioID)
        return nextStore
    }
}
