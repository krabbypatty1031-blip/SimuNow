import Foundation
import Observation
import SimuCore
import SimuSimulation
import SimuVisualization

public protocol PreviewDelayClock: Sendable { func waitForDebounce() async throws }
public struct ContinuousPreviewDelayClock: PreviewDelayClock {
    public init() {}
    public func waitForDebounce() async throws { try await Task.sleep(for: .milliseconds(250)) }
}
public struct PreviewWorkspaceInput: Equatable, Sendable {
    public let project: ProjectDocument?
    public let scenarioID: UUID?
    public let configuration: AnalysisConfiguration?
    public let additionalIssues: [ValidationIssue]
    public init(
        project: ProjectDocument?, scenarioID: UUID?, configuration: AnalysisConfiguration?,
        additionalIssues: [ValidationIssue] = []
    ) {
        self.project = project
        self.scenarioID = scenarioID
        self.configuration = configuration
        self.additionalIssues = additionalIssues
    }
}
/// No source of project truth. The store / native document binding provide immutable input values.
@MainActor @Observable
public final class PreviewCoordinator {
    public let analysis: AnalysisCoordinator
    public private(set) var enabled = false
    public var showPaths = true
    public private(set) var isPending = false
    public private(set) var currentInputHash: String?
    public private(set) var currentScenarioID: UUID?
    public private(set) var readiness: AnalysisReadiness?
    public private(set) var inputFailure: String?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let clock: any PreviewDelayClock
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var lastInput: PreviewWorkspaceInput?
    @ObservationIgnored private var request: LocalAnalysisRequest?
    public init(
        client: any LocalAnalysisSubmitting, clock: any PreviewDelayClock = ContinuousPreviewDelayClock()
    ) {
        analysis = .init(client: client)
        self.clock = clock
    }
    deinit { pending?.cancel() }
    public var currentResult: LocalAnalysisResult? {
        guard enabled, !isPending, let hash = currentInputHash, let scenario = currentScenarioID else {
            return nil
        }
        return analysis.result(scenarioID: scenario, inputHash: hash)
    }
    /// Task status belongs to the same frozen request as the displayed input.
    /// Old terminal state remains history while configuration/debounce changes.
    public var currentStage: LocalAnalysisStage? {
        guard enabled, !isPending, let request,
            request.identity.scenarioID == currentScenarioID,
            request.identity.inputHash == currentInputHash,
            analysis.activeIdentity == request.identity
        else { return nil }
        return analysis.stage
    }
    public var currentFailure: AnalysisMissingReason? {
        currentStage == .failed ? analysis.failure : nil
    }
    public var overlay: RoomSceneOverlay {
        guard showPaths, let result = currentResult else { return .empty }
        return (try? AirflowOverlayDescriptor(result: result).scene) ?? .empty
    }
    public func setEnabled(
        _ value: Bool, input: PreviewWorkspaceInput, registry: ModelRegistry,
        persist: @escaping @MainActor @Sendable (NativeAnalysisArtifact) throws -> Void
    ) {
        enabled = value
        if value { update(input, registry: registry, persist: persist) } else { stop() }
    }
    public func update(
        _ input: PreviewWorkspaceInput, registry: ModelRegistry,
        persist: @escaping @MainActor @Sendable (NativeAnalysisArtifact) throws -> Void
    ) {
        lastInput = input
        guard enabled else { return }
        generation &+= 1
        let token = generation
        pending?.cancel()
        isPending = true
        inputFailure = nil
        readiness = nil
        currentInputHash = nil
        currentScenarioID = input.scenarioID
        guard input.project != nil, input.scenarioID != nil else {
            analysis.stop()
            request = nil
            isPending = false
            inputFailure = "先打开项目并选择一个方案。"
            return
        }
        guard input.configuration != nil else {
            analysis.stop()
            request = nil
            isPending = false
            // No adopted configuration is a normal waiting-for-user state.
            return
        }
        // Immediately mask stale display, while keeping its immutable historical result.
        if request?.identity.scenarioID != input.scenarioID
            || request?.resolvedInput.snapshot.projectID != input.project?.id
        {
            analysis.stop()
        }
        let clock = clock
        pending = Task { [weak self] in
            do {
                try await clock.waitForDebounce()
                try Task.checkCancellation()
                guard let project = input.project, let scenario = input.scenarioID,
                    let config = input.configuration
                else { return }
                let task = Task.detached { () throws -> (LocalAnalysisRequest, AnalysisReadiness) in
                    try Task.checkCancellation()
                    let prepared = try AnalysisInputResolver(registry: registry).prepare(
                        project: project, scenarioID: scenario, method: .init(kind: .airflowPreview),
                        configuration: config, additionalIssues: input.additionalIssues)
                    return (prepared.request, prepared.readiness)
                }
                let (captured, readiness) = try await withTaskCancellationHandler(
                    operation: { try await task.value }, onCancel: { task.cancel() })
                try Task.checkCancellation()
                guard let self, self.generation == token, self.enabled else { return }
                self.isPending = false
                self.readiness = readiness
                self.currentInputHash = captured.identity.inputHash
                if self.request?.identity.scenarioID == captured.identity.scenarioID,
                    self.request?.identity.inputHash == captured.identity.inputHash,
                    self.analysis.result(
                        scenarioID: captured.identity.scenarioID, inputHash: captured.identity.inputHash)
                        != nil
                        || self.analysis.activeIdentity == self.request?.identity
                            && self.analysis.stage?.isTerminal != true
                {
                    return
                }
                self.request = captured
                self.analysis.start(captured, persist: persist)
            } catch is CancellationError {} catch {
                guard let self, self.generation == token else { return }
                self.analysis.stop()
                self.isPending = false
                self.currentInputHash = nil
                self.request = nil
                if case AnalysisResolutionError.notReady(let readiness) = error {
                    self.readiness = readiness
                    self.inputFailure = "输入或档案尚未就绪，请查看缺项。"
                } else {
                    self.inputFailure = String(describing: error)
                }
            }
        }
    }
    public func retry(
        registry: ModelRegistry,
        persist: @escaping @MainActor @Sendable (NativeAnalysisArtifact) throws -> Void
    ) {
        guard let input = lastInput else { return }
        request = nil
        update(input, registry: registry, persist: persist)
    }
    public func cancel() {
        stop()
        inputFailure = "预览已取消；旧记录仍属于原输入。"
    }
    public func stop() {
        generation &+= 1
        pending?.cancel()
        pending = nil
        analysis.stop()
        isPending = false
        request = nil
        currentInputHash = nil
        currentScenarioID = nil
        readiness = nil
    }
    public func resetSession() {
        stop()
        enabled = false
        lastInput = nil
        inputFailure = nil
        analysis.resetSession()
    }
}
