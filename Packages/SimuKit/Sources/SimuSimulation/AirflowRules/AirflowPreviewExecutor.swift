import Foundation
import SimuCore

public struct AirflowPreviewExecutor: LocalAnalysisExecutor {
    public let method = AnalysisMethod(kind: .airflowPreview)
    public let registry: ModelRegistry
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    public func execute(_ request: LocalAnalysisRequest, progress: @escaping @Sendable (Double) async -> Void)
        async throws -> LocalAnalysisExecution
    {
        try Task.checkCancellation()
        let input = try AirflowPreviewInput(request: request, registry: registry)
        await progress(0.1)
        let trace = try PreviewPathTracer.trace(input)
        await progress(0.65)
        let relations = try AirflowTargetAssessment.assess(input)
        try Task.checkCancellation()
        var notes = input.notes
        if !trace.rejections.isEmpty { notes.append("\(trace.rejections.count) 个截面发射点位于域外或家具内，已明确跳过。") }
        if relations.isEmpty || relations.allSatisfy({ $0.state == .notEvaluated }) {
            notes.append("无可评价关注点；只显示几何路径，不生成关注点建议。")
        }
        let payload = AirflowPreviewPayload(
            profileID: input.field.profile.configuration.profileID,
            profileVersion: input.field.profile.configuration.profileVersion,
            paths: trace.paths, relations: relations, validEmissionCount: trace.paths.count, notes: notes,
            sourcePortID: input.sourcePortID,
            geometryToleranceMeters: input.field.profile.geometryToleranceMeters,
            wallSourceOffsetMeters: input.isWallSource ? input.field.profile.wallSourceOffsetMeters : 0,
            emissionRejections: trace.rejections)
        await progress(1)
        return .init(payload: .airflowPreview(payload), checks: .init(state: .passed))
    }
}
extension LocalAnalysisClient {
    /// Only implemented methods are registered. All methods use the same App scheduling budget.
    public static func production(registry: ModelRegistry = .builtIn) -> LocalAnalysisClient {
        do {
            return try .init(executors: [AirflowPreviewExecutor(registry: registry), PowerEstimateExecutor(), SteadyHeatBalanceExecutor()], registry: registry)
        } catch { preconditionFailure("Invalid built-in local analysis registry: \(error)") }
    }
}
