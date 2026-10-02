import Foundation
import Observation
import SimuCore
import SimuSimulation

@MainActor
@Observable
public final class WorkspaceStore {
    public var selection: WorkspaceDestination? = .workspace
    public private(set) var project: ProjectDocument?
    public var selectedScenarioID: UUID?
    public private(set) var baselineScenarioID: UUID?
    public private(set) var templateID: String?
    public private(set) var templateVersion: Int?
    public private(set) var revision: UInt64 = 0
    public private(set) var analysisConfiguration: AnalysisConfigurationStore?
    public private(set) var capturedInput: ScenarioInputSnapshot?
    public var presentedError: String?
    public let modelRegistry: ModelRegistry
    public let projectValidator: ProjectValidator
    public let localAnalysisClient: any LocalAnalysisSubmitting
    public let simulationClient: any SimulationClient
    private var undoHistory: [WorkspaceHistoryEntry] = []
    private var redoHistory: [WorkspaceHistoryEntry] = []
    @ObservationIgnored public var onDocumentChange: (@MainActor (WorkspaceProjectState) -> Void)?
    @ObservationIgnored public var validateDocumentChange: (@MainActor (WorkspaceProjectState) throws -> Void)?

    public init(simulationClient: any SimulationClient = UnconfiguredSimulationClient(),
                modelRegistry: ModelRegistry = .builtIn, projectValidator: ProjectValidator = ProjectValidator(),
                localAnalysisClient: any LocalAnalysisSubmitting = LocalAnalysisClient.unavailable) {
        self.modelRegistry = modelRegistry
        self.projectValidator = projectValidator
        self.simulationClient = simulationClient
        self.localAnalysisClient = localAnalysisClient
    }

    public var currentScenario: Scenario? {
        project?.scenarios.first { $0.id == selectedScenarioID }
    }
    public var canUndo: Bool { !undoHistory.isEmpty }
    public var canRedo: Bool { !redoHistory.isEmpty }
    public var undoActionName: String? { undoHistory.last?.name }
    public var redoActionName: String? { redoHistory.last?.name }

    /// The complete project is checked for integrity; a selected scenario is checked
    /// separately for input preparation so unfinished candidates do not block it.
    public var integrityReport: ValidationReport {
        guard let project else { return .init(issues: []) }
        return report(for: project)
    }
    public var selectedScenarioReport: ValidationReport {
        guard var projected = project, let id = selectedScenarioID,
              let index = projected.scenarios.firstIndex(where: { $0.id == id }) else {
            return .init(issues: [.init(code: "scenario_required", path: "/scenarios", blocks: [.inputPreparation], message: "选择一个方案。")])
        }
        projected.scenarios = [projected.scenarios[index]]
        let result = report(for: projected)
        return .init(issues: result.issues.map { issue in
            let prefix = "/scenarios/0"
            let path = issue.path == prefix || issue.path.hasPrefix(prefix + "/")
                ? "/scenarios/\(index)" + issue.path.dropFirst(prefix.count) : issue.path
            return .init(code: issue.code, path: path, entityID: issue.entityID,
                         severity: issue.severity, blocks: issue.blocks, message: issue.message)
        })
    }

    /// Installs a document read by the document layer. This also accepts repairable
    /// semantic errors; structural decoding has already occurred before this call.
    public func load(_ project: ProjectDocument, baselineScenarioID: UUID? = nil,
                     templateID: String? = nil, templateVersion: Int? = nil, analysisConfiguration: AnalysisConfigurationStore? = nil) {
        self.analysisConfiguration = analysisConfiguration
        self.project = project
        self.baselineScenarioID = baselineScenarioID
        self.templateID = templateID
        self.templateVersion = templateVersion
        selectedScenarioID = baselineScenarioID ?? project.scenarios.first?.id
        undoHistory.removeAll(); redoHistory.removeAll()
        capturedInput = nil
        revision &+= 1
    }

    public func replaceProject(_ candidate: ProjectDocument, actionName: String) throws {
        var next = state(for: candidate)
        if let id = next.baselineScenarioID, !candidate.scenarios.contains(where: { $0.id == id }) {
            throw WorkspaceEditingError.invalidBaseline
        }
        if next.baselineScenarioID == nil && candidate.scenarios.count == 1 {
            next.baselineScenarioID = candidate.scenarios[0].id
        }
        try commit(next, actionName: actionName)
    }

    public func applyTemplate(_ project: ProjectDocument, templateID: String, templateVersion: Int) throws {
        let next = WorkspaceProjectState(project: project, baselineScenarioID: project.scenarios.first?.id,
                                         templateID: templateID, templateVersion: templateVersion)
        try commit(next, actionName: "应用模板")
        selectedScenarioID = next.baselineScenarioID
    }

    public func createRoomProject(_ project: ProjectDocument) throws {
        try commit(.init(project: project, baselineScenarioID: project.scenarios.first?.id), actionName: "创建房间")
    }

    public func setBaseline(_ id: UUID) throws {
        guard let project, project.scenarios.contains(where: { $0.id == id }) else {
            throw WorkspaceEditingError.invalidBaseline
        }
        var next = state(for: project); next.baselineScenarioID = id
        try commit(next, actionName: "设置基准方案")
    }

    /// Changes scenario data and the baseline marker atomically (including deletion).
    public func replaceScenarios(_ candidate: ProjectDocument, baselineScenarioID: UUID?, actionName: String) throws {
        var next = state(for: candidate); next.baselineScenarioID = baselineScenarioID
        try commit(next, actionName: actionName)
    }

    public func updateAnalysisConfiguration(_ configuration: AnalysisConfigurationStore, actionName: String = "修改分析配置") throws {
        guard let project else { throw WorkspaceEditingError.noScenario }
        var next = state(for: project); next.analysisConfiguration = configuration
        try commit(next, actionName: actionName)
    }

    public func replaceProjectAndAnalysis(_ candidate: ProjectDocument, configuration: AnalysisConfigurationStore, actionName: String) throws {
        var next = state(for: candidate); next.analysisConfiguration = configuration
        try commit(next, actionName: actionName)
    }

    public func undo() {
        guard let previous = undoHistory.popLast(), let project else { return }
        redoHistory.append(.init(name: previous.name, state: state(for: project)))
        install(previous.state)
    }
    public func redo() {
        guard let next = redoHistory.popLast(), let project else { return }
        undoHistory.append(.init(name: next.name, state: state(for: project)))
        install(next.state)
    }

    @discardableResult public func captureSelectedInput() throws -> ScenarioInputSnapshot {
        guard let project, let selectedScenarioID else { throw WorkspaceEditingError.noScenario }
        guard integrityReport.passes(.projectIntegrity) else {
            throw WorkspaceEditingError.validation(integrityReport.issues.filter { $0.blocks.contains(.projectIntegrity) })
        }
        let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: selectedScenarioID)
        _ = try ProjectCodec(registry: modelRegistry).encodeSnapshot(snapshot)
        capturedInput = snapshot
        return snapshot
    }

    public func prepareLocalAnalysis(method: AnalysisMethod, configuration: AnalysisConfiguration,
                                     runID: UUID = UUID(), additionalIssues: [ValidationIssue] = []) async throws -> LocalAnalysisRequest {
        guard let project, let selectedScenarioID else { throw WorkspaceEditingError.noScenario }
        let registry = modelRegistry
        let task = Task.detached {
            try AnalysisInputResolver(registry: registry).request(project: project, scenarioID: selectedScenarioID,
                method: method, configuration: configuration, runID: runID, additionalIssues: additionalIssues)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func report(for value: ProjectDocument) -> ValidationReport {
        do { return try projectValidator.validate(value, registry: modelRegistry) }
        catch { return .init(issues: [.init(code: "contract_error", path: "", message: String(describing: error))]) }
    }
    private func state(for value: ProjectDocument) -> WorkspaceProjectState {
        var configuration = analysisConfiguration?.projectID == value.id ? analysisConfiguration : nil
        configuration?.entries.removeAll { entry in !value.scenarios.contains { $0.id == entry.scenarioID } }
        return .init(project: value, baselineScenarioID: baselineScenarioID, templateID: templateID, templateVersion: templateVersion,
                     analysisConfiguration: configuration)
    }
    private func commit(_ next: WorkspaceProjectState, actionName: String) throws {
        if let configuration = next.analysisConfiguration {
            guard configuration.projectID == next.project.id, configuration.entries.allSatisfy({ e in next.project.scenarios.contains { $0.id == e.scenarioID } }) else {
                throw NativeArtifactError.identityMismatch
            }
            _ = try NativeAnalysisCodec(registry: modelRegistry).encodeConfiguration(configuration)
        }
        if let baseline = next.baselineScenarioID, !next.project.scenarios.contains(where: { $0.id == baseline }) {
            throw WorkspaceEditingError.invalidBaseline
        }
        let result = try projectValidator.validate(next.project, registry: modelRegistry)
        let errors = result.issues.filter { $0.blocks.contains(.projectIntegrity) }
        if !errors.isEmpty {
            // A repair transaction may retain existing issues but cannot introduce
            // new ones. Stable entity IDs prevent array reordering changing identity.
            let previous = Dictionary(integrityReport.issues.filter { $0.blocks.contains(.projectIntegrity) }
                .map { (Self.issueKey($0, in: project), 1) }, uniquingKeysWith: +)
            let nextCounts = Dictionary(errors.map { (Self.issueKey($0, in: next.project), 1) }, uniquingKeysWith: +)
            guard nextCounts.allSatisfy({ $0.value <= previous[$0.key, default: 0] }) else {
                throw WorkspaceEditingError.validation(errors)
            }
        }
        if let project {
            let old = state(for: project)
            if old == next { return }
            try validateDocumentChange?(next)
            undoHistory.append(.init(name: actionName, state: old))
            if undoHistory.count > 60 { undoHistory.removeFirst() }
        }
        else { try validateDocumentChange?(next) }
        redoHistory.removeAll()
        install(next)
    }
    private static func issueKey(_ issue: ValidationIssue, in project: ProjectDocument?) -> String {
        let parts = issue.path.split(separator: "/")
        let scope: String
        if parts.count > 1, parts[0] == "scenarios", let index = Int(parts[1]), let project,
           project.scenarios.indices.contains(index) { scope = project.scenarios[index].id.uuidString }
        else { scope = "project" }
        let path = issue.path.split(separator: "/").filter { Int($0) == nil }.joined(separator: "/")
        return "\(scope)|\(issue.code)|\(issue.entityID?.uuidString ?? "")|\(path)"
    }
    private func install(_ value: WorkspaceProjectState) {
        // Only this path publishes edits back to the native document binding.
        onDocumentChange?(value)
        project = value.project
        analysisConfiguration = value.analysisConfiguration
        baselineScenarioID = value.baselineScenarioID
        templateID = value.templateID
        templateVersion = value.templateVersion
        if !value.project.scenarios.contains(where: { $0.id == selectedScenarioID }) {
            selectedScenarioID = value.baselineScenarioID ?? value.project.scenarios.first?.id
        }
        revision &+= 1
    }
}

public struct WorkspaceProjectState: Equatable, Sendable {
    public let project: ProjectDocument
    public var baselineScenarioID: UUID?
    public var templateID: String?
    public var templateVersion: Int?
    public var analysisConfiguration: AnalysisConfigurationStore?
    public init(project: ProjectDocument, baselineScenarioID: UUID? = nil,
                templateID: String? = nil, templateVersion: Int? = nil, analysisConfiguration: AnalysisConfigurationStore? = nil) {
        self.analysisConfiguration = analysisConfiguration
        self.project = project; self.baselineScenarioID = baselineScenarioID
        self.templateID = templateID; self.templateVersion = templateVersion
    }
}
private struct WorkspaceHistoryEntry {
    let name: String
    let state: WorkspaceProjectState
}
public enum WorkspaceEditingError: Error, LocalizedError {
    case invalidBaseline, noScenario, validation([ValidationIssue])
    public var errorDescription: String? {
        switch self {
        case .invalidBaseline: "请先选择仍然存在的基准方案，再删除原基准。"
        case .noScenario: "请先创建或选择一个方案。"
        case .validation(let issues): issues.prefix(5).map(ValidationPresentation.describe).joined(separator: "\n")
        }
    }
}

public enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case workspace, scenarios, runs, reports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .workspace: "房间工作区"
        case .scenarios: "方案对比"
        case .runs: "计算任务"
        case .reports: "分析报告"
        }
    }

    public var symbol: String {
        switch self {
        case .workspace: "cube.transparent"
        case .scenarios: "square.stack.3d.up"
        case .runs: "waveform.path"
        case .reports: "doc.text"
        }
    }
}
