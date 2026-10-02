import Foundation

public enum ValidationTarget: String, Codable, Sendable { case projectIntegrity, inputPreparation }
public enum ValidationSeverity: String, Codable, Sendable { case warning, error }
public struct ValidationIssue: Codable, Equatable, Sendable {
    public let code: String
    public let path: String
    public let entityID: UUID?
    public let severity: ValidationSeverity
    public let blocks: [ValidationTarget]
    public let message: String
    public init(code: String, path: String, entityID: UUID? = nil, severity: ValidationSeverity = .error,
                blocks: [ValidationTarget] = [.projectIntegrity,.inputPreparation], message: String) {
        self.code = code; self.path = path; self.entityID = entityID; self.severity = severity; self.blocks = blocks; self.message = message
    }
}
public struct ValidationReport: Equatable, Sendable {
    public let issues: [ValidationIssue]
    public init(issues: [ValidationIssue]) { self.issues = issues }
    public func passes(_ target: ValidationTarget) -> Bool { !issues.contains { $0.blocks.contains(target) } }
}
public protocol ProjectValidationRule: Sendable {
    func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue]
}
public struct InputRequirements: ProjectValidationRule, Sendable {
    public let requiredPaths: [String]
    public let fullDaySchedulePaths: [String]
    public init(requiredPaths: [String] = [], fullDaySchedulePaths: [String] = []) {
        self.requiredPaths = requiredPaths; self.fullDaySchedulePaths = fullDaySchedulePaths
    }
    public func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue] {
        let node = try JSONTreeCoding.encode(project)
        var issues: [ValidationIssue] = []
        for path in requiredPaths {
            if let value = node.at(pointer:path), value != .null, value["state"]?.string != "unknown" { continue }
            issues.append(.init(code:"required_input",path:path,blocks:[.inputPreparation],message:"Provide the input required by this adapter."))
        }
        for path in fullDaySchedulePaths {
            let items = node.at(pointer:path)?.items ?? []
            var cursor = 0.0
            for item in items {
                if item["startMinute"]?.double != cursor { cursor = -1; break }
                cursor = item["endMinute"]?.double ?? -1
            }
            if cursor != 1440 { issues.append(.init(code:"schedule_coverage",path:path,blocks:[.inputPreparation],message:"Cover the complete representative day.")) }
        }
        return issues
    }
}
public extension JSONValue {
    func at(pointer: String) -> JSONValue? {
        if pointer.isEmpty { return self }
        guard pointer.hasPrefix("/") else { return nil }
        var node = self
        for part in pointer.dropFirst().split(separator:"/",omittingEmptySubsequences:false) {
            let key = String(part).replacingOccurrences(of:"~1",with:"/").replacingOccurrences(of:"~0",with:"~")
            if let fields = node.fields, let child = fields[key] { node = child }
            else if let items = node.items, let i = Int(key), items.indices.contains(i) { node = items[i] }
            else { return nil }
        }
        return node
    }
}
