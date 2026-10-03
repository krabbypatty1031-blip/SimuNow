import Foundation

public struct ProjectCodec: Sendable {
    public let registry: ModelRegistry
    public init(registry: ModelRegistry) { self.registry = registry }
    public func decode(_ data: Data) throws -> ProjectDocument {
        let node = try JSONValue(data: data)
        guard let version = node["schemaVersion"]?.double, let integer = Int(exactly: version) else {
            throw ProjectDataError.contract("schemaVersion")
        }
        guard integer == 2 else { throw ProjectDataError.unsupportedVersion(integer) }
        try WireSchema.validate(node, schema: ContractSchemas.project)
        let project = try JSONTreeCoding.decode(ProjectDocument.self, from: node)
        try validatePayloads(project.geometry, inputs: project.scenarios.map(\.inputs))
        return project
    }
    public func encode(_ project: ProjectDocument) throws -> Data {
        try validatedProjectTree(project).data()
    }
    /// Same structural and extension checks as encode, without serializing unused bytes.
    public func validate(_ project: ProjectDocument) throws { _ = try validatedProjectTree(project) }
    private func validatedProjectTree(_ project: ProjectDocument) throws -> JSONValue {
        let node = try JSONTreeCoding.encode(project)
        try WireSchema.validate(node, schema: ContractSchemas.project)
        try validatePayloads(project.geometry, inputs: project.scenarios.map(\.inputs))
        return node
    }
    public func decodeSnapshot(_ data: Data) throws -> ScenarioInputSnapshot {
        let node = try JSONValue(data: data)
        try WireSchema.validate(node, schema: ContractSchemas.snapshot)
        let result = try JSONTreeCoding.decode(ScenarioInputSnapshot.self, from: node)
        try validatePayloads(result.geometry, inputs: [result.inputs])
        return result
    }
    public func encodeSnapshot(_ value: ScenarioInputSnapshot) throws -> Data {
        try validatedSnapshotTree(value).data()
    }
    public func validateSnapshot(_ value: ScenarioInputSnapshot) throws {
        _ = try validatedSnapshotTree(value)
    }
    private func validatedSnapshotTree(_ value: ScenarioInputSnapshot) throws -> JSONValue {
        let node = try JSONTreeCoding.encode(value)
        try WireSchema.validate(node, schema: ContractSchemas.snapshot)
        try validatePayloads(value.geometry, inputs: [value.inputs])
        return node
    }
    private func validatePayloads(_ geometry: ProjectGeometry, inputs: [ScenarioInputs]) throws {
        func resolve(_ category: String, _ record: ExtensionRecord) throws {
            if registry.registration(category: category, record: record) == nil,
                registry.registrations.contains(where: {
                    $0.kind == record.kind && $0.version == record.payloadVersion
                })
            {
                throw ProjectDataError.contract("wrong extension category")
            }
            _ = try registry.resolve(category: category, record: record)
        }
        for room in geometry.rooms { try resolve("room", room.shape) }
        for obstacle in geometry.obstacles { try resolve("obstacle", obstacle.shape) }
        for input in inputs { for device in input.hvac { try resolve("hvac", device.definition) } }
    }
}
public struct MigrationResult: Sendable {
    public let project: ProjectDocument
    public let notes: [String]
}
public enum ProjectMigrator {
    public static func migrate(_ data: Data) throws -> MigrationResult {
        let node = try JSONValue(data: data)
        guard
            Set(node.fields?.keys.map { $0 } ?? [])
                == Set(["schemaVersion", "id", "name", "spaceType", "lengthUnit", "coordinateSystem"]),
            node["schemaVersion"]?.double == 1, node["lengthUnit"]?.string == "m",
            node["coordinateSystem"]?.string == "rightHandedZUp"
        else { throw ProjectDataError.contract("invalid v1 draft") }
        let draft = try JSONTreeCoding.decode(ProjectDraft.self, from: node)
        return MigrationResult(
            project: ProjectDocument(
                id: draft.id, name: draft.name, spaceType: draft.spaceType, geometry: .init()),
            notes: ["Geometry and scenario inputs remain incomplete; no physical defaults were invented."])
    }
}
public enum ScenarioSnapshotBuilder {
    /// Captures data only. Does not claim engine availability or simulation readiness.
    public static func capture(_ project: ProjectDocument, scenarioID: UUID) throws -> ScenarioInputSnapshot {
        guard
            project.schemaVersion == 2 && project.lengthUnit == "m"
                && project.coordinateSystem == "rightHandedZUp"
        else { throw ProjectDataError.contract("invalid project metadata") }
        guard project.scenarios.filter({ $0.id == scenarioID }).count == 1,
            let scenario = project.scenarios.first(where: { $0.id == scenarioID })
        else { throw ProjectDataError.missingScenario(scenarioID) }
        return .init(
            projectID: project.id, scenarioID: scenario.id, lengthUnit: project.lengthUnit,
            coordinateSystem: project.coordinateSystem,
            geometry: project.geometry, inputs: scenario.inputs, evaluation: scenario.evaluation)
    }
}
