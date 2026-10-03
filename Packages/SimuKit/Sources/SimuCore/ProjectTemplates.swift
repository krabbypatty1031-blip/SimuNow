import Foundation

/// Frozen template plus the fields a user should change versus omitted envelope/weather.
public struct ProjectTemplate: Codable, Equatable, Sendable {
    public var overridable: [String]
    public var lockedAssumptions: [String]
    public var project: ProjectDraft

    public init(overridable: [String], lockedAssumptions: [String], project: ProjectDraft) {
        self.overridable = overridable
        self.lockedAssumptions = lockedAssumptions
        self.project = project
    }

    /// Current edit is a new identity; baseline keeps the template snapshot and has no results.
    public func instantiate(currentID: UUID = UUID(), scenarioID: UUID = UUID()) -> DesignSession {
        var current = project
        current.id = currentID
        return DesignSession(
            current: current,
            baseline: project,
            baselineScenarioID: scenarioID,
            overridable: overridable,
            lockedAssumptions: lockedAssumptions
        )
    }
}

/// Baseline input snapshot versus the in-memory edit. Not a solved run.
public struct DesignSession: Equatable, Sendable {
    public var current: ProjectDraft
    public var baseline: ProjectDraft
    public var baselineScenarioID: UUID
    public var overridable: [String]
    public var lockedAssumptions: [String]
}

public enum ProjectTemplatesError: Error, Equatable, LocalizedError, Sendable {
    case unknownTemplate(String)

    public var errorDescription: String? {
        switch self {
        case .unknownTemplate(let name):
            return "没有名为 \(name) 的内置模板"
        }
    }
}

public enum ProjectTemplates {
    public static func office(from directory: URL) throws -> ProjectTemplate {
        try load(from: directory.appendingPathComponent("office.json"))
    }

    public static func classroom(from directory: URL) throws -> ProjectTemplate {
        try load(from: directory.appendingPathComponent("classroom.json"))
    }

    /// Sandboxed apps cannot read the repo `Fixtures/` tree; decode the compiled-in JSON instead.
    public static func bundled(named name: String) throws -> ProjectTemplate {
        guard let data = BundledTemplateJSON.data(named: name) else {
            throw ProjectTemplatesError.unknownTemplate(name)
        }
        return try JSONDecoder().decode(ProjectTemplate.self, from: data)
    }

    public static func load(from url: URL) throws -> ProjectTemplate {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectTemplate.self, from: data)
    }

    /// Compile-time source location for tests and unsandboxed tools. Not used by the Mac app.
    public static func repositoryTemplatesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/templates")
    }
}
