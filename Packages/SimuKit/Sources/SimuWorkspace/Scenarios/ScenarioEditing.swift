import Foundation
import SimuCore

public enum ScenarioEditingError: LocalizedError, Equatable, Sendable {
    case missingScenario(UUID)
    case invalidName
    case invalidBaseline
    case replacementRequired
    case invalidProject([ValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .missingScenario: "找不到所选方案，请重新选择。"
        case .invalidName: "方案名称不能为空。"
        case .invalidBaseline: "基准方案或替代方案必须属于当前项目。"
        case .replacementRequired: "删除基准方案前，请明确选择另一个方案作为基准。"
        case .invalidProject(let issues): "项目完整性检查未通过：\(issues.first?.message ?? "请先修复输入冲突")"
        }
    }
}

public struct ScenarioDeletion: Equatable, Sendable {
    public let project: ProjectDocument
    public let baselineScenarioID: UUID?
}

/// A value-only checkpoint includes shared geometry as well as all scenarios.
/// Restoring it is one complete-project transaction, never a partial geometry restore.
public struct ProjectEditCheckpoint: Equatable, Sendable {
    public let project: ProjectDocument
    public let baselineScenarioID: UUID?

    public static func capture(_ project: ProjectDocument, baselineScenarioID: UUID? = nil,
                               registry: ModelRegistry = .builtIn, validator: ProjectValidator = .init()) throws -> Self {
        try ScenarioEditing.validateBaseline(baselineScenarioID, in: project)
        let report = try validator.validate(project, registry: registry)
        guard report.passes(.projectIntegrity) else {
            throw ScenarioEditingError.invalidProject(report.issues.filter { $0.blocks.contains(.projectIntegrity) })
        }
        return .init(project: project, baselineScenarioID: baselineScenarioID)
    }
}

/// Captures inputs plus their preparation issues. Passing that check still does not imply an available engine.
public struct ScenarioEditSnapshot: Equatable, Sendable {
    public let input: ScenarioInputSnapshot
    public let validation: ValidationReport
}

public enum ScenarioEditing {
    public static func copy(_ project: ProjectDocument, scenarioID: UUID, name: String) throws -> ProjectDocument {
        let index = try scenarioIndex(scenarioID, in: project)
        let cleanName = try validatedName(name)
        var copy = project.scenarios[index]
        copy.id = UUID()
        copy.name = cleanName
        var edited = project
        edited.scenarios.append(copy)
        return edited
    }

    public static func rename(_ project: ProjectDocument, scenarioID: UUID, name: String) throws -> ProjectDocument {
        let index = try scenarioIndex(scenarioID, in: project)
        var edited = project
        edited.scenarios[index].name = try validatedName(name)
        return edited
    }

    public static func delete(_ project: ProjectDocument, scenarioID: UUID, baselineScenarioID: UUID?,
                              replacementBaselineID: UUID? = nil) throws -> ScenarioDeletion {
        let index = try scenarioIndex(scenarioID, in: project)
        try validateBaseline(baselineScenarioID, in: project)
        if let replacementBaselineID {
            guard replacementBaselineID != scenarioID else { throw ScenarioEditingError.invalidBaseline }
            try validateBaseline(replacementBaselineID, in: project)
        }
        if baselineScenarioID == scenarioID && replacementBaselineID == nil {
            throw ScenarioEditingError.replacementRequired
        }
        var edited = project
        edited.scenarios.remove(at: index)
        return .init(project: edited, baselineScenarioID: baselineScenarioID == scenarioID ? replacementBaselineID : baselineScenarioID)
    }

    public static func validateBaseline(_ id: UUID?, in project: ProjectDocument) throws {
        guard let id else { return }
        guard project.scenarios.filter({ $0.id == id }).count == 1 else { throw ScenarioEditingError.invalidBaseline }
    }

    public static func snapshot(_ project: ProjectDocument, scenarioID: UUID,
                                registry: ModelRegistry = .builtIn, validator: ProjectValidator = .init()) throws -> ScenarioEditSnapshot {
        let index = try scenarioIndex(scenarioID, in: project)
        let fullReport = try validator.validate(project, registry: registry)
        guard fullReport.passes(.projectIntegrity) else {
            throw ScenarioEditingError.invalidProject(fullReport.issues.filter { $0.blocks.contains(.projectIntegrity) })
        }
        var projection = project
        projection.scenarios = [project.scenarios[index]]
        let report = try validator.validate(projection, registry: registry)
        let mapped = report.issues.map { issue in
            let prefix = "/scenarios/0"
            let path = issue.path == prefix || issue.path.hasPrefix(prefix + "/")
                ? "/scenarios/\(index)" + issue.path.dropFirst(prefix.count) : issue.path
            return ValidationIssue(code: issue.code, path: path, entityID: issue.entityID,
                                   severity: issue.severity, blocks: issue.blocks, message: issue.message)
        }
        return .init(input: try ScenarioSnapshotBuilder.capture(project, scenarioID: scenarioID), validation: .init(issues: mapped))
    }

    private static func scenarioIndex(_ id: UUID, in project: ProjectDocument) throws -> Int {
        guard project.scenarios.filter({ $0.id == id }).count == 1,
              let index = project.scenarios.firstIndex(where: { $0.id == id }) else {
            throw ScenarioEditingError.missingScenario(id)
        }
        return index
    }

    private static func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ScenarioEditingError.invalidName }
        return value
    }
}
