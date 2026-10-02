import Foundation
import SimuCore

/// Package bookkeeping is separate from the shared physical-input schema.
public struct ProjectPackageMetadata: Codable, Equatable, Sendable {
    public var packageVersion: Int
    public var baselineScenarioID: UUID?
    public var templateID: String?
    public var templateVersion: Int?

    public init(packageVersion: Int = 1, baselineScenarioID: UUID? = nil,
                templateID: String? = nil, templateVersion: Int? = nil) {
        self.packageVersion = packageVersion
        self.baselineScenarioID = baselineScenarioID
        self.templateID = templateID
        self.templateVersion = templateVersion
    }

    func validate() throws {
        guard packageVersion == 1 else { throw ProjectPackageError.unsupportedPackageVersion(packageVersion) }
        guard (templateID == nil) == (templateVersion == nil) else {
            throw ProjectPackageError.invalidMetadata("模板标识与版本必须同时提供。")
        }
        if let templateID {
            guard !templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  templateID.utf8.count <= 256, (templateVersion ?? 0) > 0 else {
                throw ProjectPackageError.invalidMetadata("模板标识不能为空，模板版本必须为正整数。")
            }
        }
    }

    static func decode(_ data: Data) throws -> Self {
        let tree = try JSONValue(data: data)
        guard let fields = tree.fields, fields["packageVersion"] != nil,
              Set(fields.keys).isSubset(of: ["packageVersion", "baselineScenarioID", "templateID", "templateVersion"]),
              !fields.values.contains(.null) else {
            throw ProjectPackageError.invalidMetadata("元数据缺少包版本，或包含本版本无法解释的字段。")
        }
        let value = try JSONTreeCoding.decode(Self.self, from: tree)
        try value.validate()
        return value
    }

    func encoded() throws -> Data {
        try validate()
        return try JSONTreeCoding.encode(self).data()
    }
}

public enum ProjectPackageError: Error, Equatable, Sendable, LocalizedError {
    case invalidPackage(String)
    case missingRequiredFile(String)
    case unsupportedPackageVersion(Int)
    case invalidMetadata(String)
    case resourceLimit(String)
    case repairRequired([ValidationIssue])
    case explicitMigrationRequired

    public var errorDescription: String? {
        switch self {
        case .invalidPackage(let reason): return "项目包无法读取：\(reason)"
        case .missingRequiredFile(let name): return "项目包缺少必需文件 \(name)。"
        case .unsupportedPackageVersion(let version): return "不支持项目包版本 \(version)，原文件未被改写。"
        case .invalidMetadata(let reason): return "项目包元数据无效：\(reason)"
        case .resourceLimit(let reason): return "项目包超过导入限制：\(reason)"
        case .repairRequired(let issues): return "项目有 \(issues.count) 项完整性问题，修复后才能保存。"
        case .explicitMigrationRequired: return "这是 v1 草稿。请选择显式迁移；迁移会生成新项目并保留原文件。"
        }
    }
}

/// Fixed P2 import budget. Large future run fields need a streamed artifact store,
/// rather than unbounded loading into a SwiftUI value document.
public struct ProjectPackageLimits: Equatable, Sendable {
    public let maximumEntries: Int
    public let maximumDepth: Int
    public let maximumFileBytes: Int
    public let maximumTotalBytes: Int
    public let maximumProjectBytes: Int
    public let maximumMetadataBytes: Int

    public init(maximumEntries: Int = 4_096, maximumDepth: Int = 32,
                maximumFileBytes: Int = 64 * 1_024 * 1_024,
                maximumTotalBytes: Int = 256 * 1_024 * 1_024,
                maximumProjectBytes: Int = 8 * 1_024 * 1_024,
                maximumMetadataBytes: Int = 64 * 1_024) {
        self.maximumEntries = maximumEntries; self.maximumDepth = maximumDepth
        self.maximumFileBytes = maximumFileBytes; self.maximumTotalBytes = maximumTotalBytes
        self.maximumProjectBytes = maximumProjectBytes; self.maximumMetadataBytes = maximumMetadataBytes
    }

    public static let standard = Self()

    func validate() throws {
        guard maximumEntries > 0, maximumDepth >= 0, maximumFileBytes >= 0,
              maximumFileBytes < Int.max, maximumTotalBytes >= 0,
              maximumProjectBytes > 0, maximumProjectBytes < Int.max,
              maximumMetadataBytes > 0 else {
            throw ProjectPackageError.resourceLimit("无效的导入预算。")
        }
    }
}
