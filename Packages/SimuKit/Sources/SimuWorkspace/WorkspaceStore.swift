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
    public let runStore: RunStore

    public init(simulationClient: any SimulationClient = UnconfiguredSimulationClient(),
                runClient: (any RunClient)? = nil,
                modelRegistry: ModelRegistry = .builtIn, projectValidator: ProjectValidator = ProjectValidator()) {
        self.modelRegistry = modelRegistry
        self.projectValidator = projectValidator
        self.simulationClient = simulationClient
        self.runStore = RunStore(client: runClient ?? Self.defaultRunClient())
    }

    /// Platform default executor. macOS: the explicitly configured Python worker, else an
    /// honest unavailable client. iOS never runs local compute.
    public static func defaultRunClient() -> any RunClient {
        #if os(macOS)
        if let environment = WorkerEnvironment.resolve() {
            return LocalSimulationClient(environment: environment)
        }
        return UnavailableRunClient(reason: "未配置 Python worker。开发环境一次性设置：defaults write com.simunow.mac \(WorkerEnvironment.pythonDefaultsKey) \"<仓库>/Backend/.venv/bin/python\"；defaults write com.simunow.mac \(WorkerEnvironment.sourceDefaultsKey) \"<仓库>/Backend/src\"。或使用 SIMUNOW_WORKER_PYTHON / SIMUNOW_WORKER_SRC 环境变量。")
        #else
        return UnavailableRunClient(reason: "iOS 不执行本地计算；后续接入用户配置的远程节点。")
        #endif
    }

    public func openProject(_ project: ProjectDocument, packageURL: URL? = nil) {
        session = ProjectSession(project: project, packageURL: packageURL,
                                 registry: modelRegistry, validator: projectValidator)
        hookSession(session)
    }

    public func openPackage(at url: URL) throws {
        session = try ProjectSession.load(from: url, registry: modelRegistry)
        hookSession(session)
    }

    public func closeProject() {
        session = nil
        runStore.reset()
    }

    private func hookSession(_ session: ProjectSession?) {
        guard let session else { return }
        runStore.loadFromDisk(projectID: session.project.id)
        runStore.syncHashes(project: session.project)
        session.onMutate = { [weak runStore] project in
            runStore?.syncHashes(project: project)
        }
    }
}

public enum WorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case workspace, scenarios, runs, reports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .workspace: "布置房间"
        case .scenarios: "方案对比"
        case .runs: "用电估算"
        case .reports: "导出报告"
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
