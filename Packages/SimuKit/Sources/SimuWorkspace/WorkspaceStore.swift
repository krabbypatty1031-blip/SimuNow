import Foundation
import Observation
import SimuCore
import SimuSimulation

@MainActor
@Observable
public final class WorkspaceStore {
    public var selection: WorkspaceDestination? = .workspace
    public var project: ProjectDraft?
    public var fieldIssues: [FieldIssue] = []
    /// In-memory package location only. Never written into project.json.
    public var packageURL: URL?
    public var packageError: String?
    public var packageWarning: String?
    /// Frozen input snapshot. Editing `project` must not mutate this value.
    public var baseline: ProjectDraft?
    public var baselineScenarioID: UUID?
    public var overridable: [String] = []
    public var lockedAssumptions: [String] = []
    public let simulationClient: any SimulationClient

    public init(simulationClient: any SimulationClient = UnconfiguredSimulationClient()) {
        self.simulationClient = simulationClient
    }

    public var isPhysicalModelComplete: Bool {
        project?.hasCompletePhysicalModel == true && fieldIssues.isEmpty
    }

    public func applyRoomSize(x: Double, y: Double, z: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyRoomSize(x: x, y: y, z: z, source: .user)
        project = draft
    }

    public func applyNorthYawDegrees(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyNorthYawDegrees(value, source: .user)
        project = draft
    }

    public func upsertOpening(_ opening: Opening) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.upsertOpening(opening)
        project = draft
    }

    public func removeOpening(id: String) {
        project?.removeOpening(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func applyOpening(
        id: String,
        kind: OpeningKind,
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyOpening(id: id, kind: kind, wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    public func upsertObstacle(_ box: ObstacleBox) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.upsertObstacle(box)
        project = draft
    }

    public func applyObstacle(id: String, origin: Position3D, size: Position3D) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyObstacle(id: id, origin: origin, size: size)
        project = draft
    }

    public func removeObstacle(id: String) {
        project?.removeObstacle(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func upsertSeat(_ seat: Seat) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.upsertSeat(seat)
        project = draft
    }

    public func applySeat(id: String, position: Position3D, source: ParameterSource) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySeat(id: id, position: position, source: source)
        project = draft
    }

    public func removeSeat(id: String) {
        project?.removeSeat(id: id)
        fieldIssues = project?.allFieldIssues() ?? []
    }

    public func installDefaultSplitAC() {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.installDefaultSplitAC()
        project = draft
    }

    public func applySupplyTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySupplyTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    public func applyReturnTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyReturnTerminal(wall: wall, s0: s0, s1: s1, z0: z0, z1: z1, source: source)
        project = draft
    }

    public func applyOutdoorAirM3s(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applyOutdoorAirM3s(value, source: .user)
        project = draft
    }

    public func applySupplySpeedMs(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySupplySpeedMs(value, source: .user)
        project = draft
    }

    public func applySupplyAirflowM3s(_ value: Double) {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.applySupplyAirflowM3s(value, source: .user)
        project = draft
    }

    public func recomputeSupplyAirflowFromSpeedAndArea() {
        var draft = project ?? ProjectDraft(name: "未命名房间")
        fieldIssues = draft.recomputeSupplyAirflowFromSpeedAndArea()
        project = draft
    }

    public func openPackage(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let loaded = try ProjectPackage.load(from: url)
            project = loaded.draft
            fieldIssues = loaded.draft.allFieldIssues()
            packageURL = url.lastPathComponent == ProjectPackage.projectFileName
                ? url.deletingLastPathComponent()
                : url
            packageError = nil
            packageWarning = loaded.warnings.isEmpty ? nil : loaded.warnings.joined(separator: "\n")
            baseline = nil
            baselineScenarioID = nil
            overridable = []
            lockedAssumptions = []
        } catch {
            presentPackageError(error)
        }
    }

    public func savePackage(to url: URL) {
        guard let project else {
            packageError = "没有可保存的项目。请先填写房间或打开一个包。"
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try ProjectPackage.save(project, to: url)
            packageURL = url
            packageError = nil
        } catch {
            presentPackageError(error)
        }
    }

    public func savePackage() {
        if let packageURL {
            savePackage(to: packageURL)
        }
    }

    public func loadOfficeTemplate() {
        loadTemplate(named: "office")
    }

    public func loadClassroomTemplate() {
        loadTemplate(named: "classroom")
    }

    private func loadTemplate(named name: String) {
        do {
            apply(try ProjectTemplates.bundled(named: name))
        } catch {
            presentPackageError(error)
        }
    }

    private func apply(_ template: ProjectTemplate) {
        let session = template.instantiate()
        project = session.current
        baseline = session.baseline
        baselineScenarioID = session.baselineScenarioID
        overridable = session.overridable
        lockedAssumptions = session.lockedAssumptions
        fieldIssues = session.current.allFieldIssues()
        packageError = nil
    }

    private func presentPackageError(_ error: Error) {
        if let packageError = error as? ProjectPackageError {
            let description = packageError.errorDescription ?? "项目包错误"
            let recovery = packageError.recoverySuggestion ?? ""
            self.packageError = "\(description)。\(recovery)"
        } else {
            packageError = error.localizedDescription
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
