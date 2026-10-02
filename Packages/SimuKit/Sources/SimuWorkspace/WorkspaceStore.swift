import Foundation
import Observation
import SimuCore
import SimuSimulation

@MainActor
@Observable
public final class WorkspaceStore {
    public var destination: WorkspaceDestination? = .workspace
    /// The open project's editing session; nil shows the home screen.
    public var session: ProjectSession?
    public let modelRegistry: ModelRegistry
    public let projectValidator: ProjectValidator
    public let simulationClient: any SimulationClient

    public init(simulationClient: any SimulationClient = UnconfiguredSimulationClient(),
                modelRegistry: ModelRegistry = .builtIn, projectValidator: ProjectValidator = ProjectValidator()) {
        self.modelRegistry = modelRegistry
        self.projectValidator = projectValidator
        self.simulationClient = simulationClient
    }

    public func openProject(_ project: ProjectDocument, packageURL: URL? = nil) {
        session = ProjectSession(project: project, packageURL: packageURL,
                                 registry: modelRegistry, validator: projectValidator)
        destination = .workspace
    }

    public func openPackage(at url: URL) throws {
        session = try ProjectSession.load(from: url, registry: modelRegistry)
        destination = .workspace
    }

    public func closeProject() {
        session = nil
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
