import Foundation

/// Result of opening a `.simunow` directory package. Warnings never mean the engines ran.
public struct ProjectPackageLoad: Equatable, Sendable {
    public var draft: ProjectDraft
    public var ignoredKeys: [String]
    public var warnings: [String]

    public init(draft: ProjectDraft, ignoredKeys: [String] = [], warnings: [String] = []) {
        self.draft = draft
        self.ignoredKeys = ignoredKeys
        self.warnings = warnings
    }
}

/// Structured package I/O failure. UI must show `recoverySuggestion` instead of crashing.
public enum ProjectPackageError: Error, Equatable, LocalizedError, Sendable {
    case missingProjectJSON
    case invalidJSON(String)
    case unsupportedSchema(Int)
    case incompleteWrite
    case containsPrivateAbsolutePath

    public var errorDescription: String? {
        switch self {
        case .missingProjectJSON:
            return "项目包缺少 project.json"
        case .invalidJSON:
            return "project.json 不是合法 JSON"
        case .unsupportedSchema(let version):
            return "不支持的 schemaVersion \(version)"
        case .incompleteWrite:
            return "项目包写入未完成"
        case .containsPrivateAbsolutePath:
            return "项目 JSON 含有本机绝对路径"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .missingProjectJSON:
            return "请选择包含 project.json 的 .simunow 文件夹，或从模板重新创建。"
        case .invalidJSON:
            return "请用文本编辑器检查 project.json，或从备份重新导出。"
        case .unsupportedSchema:
            return "请把 schemaVersion 改为 1 或 2，或在新版 App 中迁移后再打开。"
        case .incompleteWrite:
            return "保留原包，稍后重试保存。不要打开可能半截写入的文件。"
        case .containsPrivateAbsolutePath:
            return "出处请写文献名，不要写入 /Users 或 /Downloads 路径。"
        }
    }
}

/// Directory package `Name.simunow/project.json`. Foundation-only; panels live in the workspace UI.
public enum ProjectPackage {
    public static let projectFileName = "project.json"
    public static let packageExtension = "simunow"
    public static let supportedSchemaVersions: Set<Int> = [1, 2]

    /// Writes a complete temp package first, then replaces the destination. Failures keep the previous JSON.
    public static func save(
        _ draft: ProjectDraft,
        to packageURL: URL,
        fileManager: FileManager = .default,
        replaceItem: ((URL, URL) throws -> Void)? = nil
    ) throws {
        let data = try encode(draft)
        try rejectPrivateAbsolutePaths(in: data)

        let tempPackage = fileManager.temporaryDirectory
            .appendingPathComponent("simunow-write-\(UUID().uuidString).\(packageExtension)", isDirectory: true)
        try fileManager.createDirectory(at: tempPackage, withIntermediateDirectories: true)
        let tempJSON = tempPackage.appendingPathComponent(projectFileName)
        try data.write(to: tempJSON, options: .atomic)

        var moved = false
        defer {
            if !moved {
                try? fileManager.removeItem(at: tempPackage)
            }
        }

        if fileManager.fileExists(atPath: packageURL.path) {
            let replace = replaceItem ?? { original, incoming in
                _ = try fileManager.replaceItemAt(original, withItemAt: incoming)
            }
            try replace(packageURL, tempPackage)
            moved = true
        } else {
            let parent = packageURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try fileManager.moveItem(at: tempPackage, to: packageURL)
            moved = true
        }
    }

    public static func load(from url: URL, fileManager: FileManager = .default) throws -> ProjectPackageLoad {
        let packageURL = packageDirectory(from: url)
        let jsonURL = packageURL.appendingPathComponent(projectFileName)
        guard fileManager.fileExists(atPath: jsonURL.path) else {
            throw ProjectPackageError.missingProjectJSON
        }
        let data: Data
        do {
            data = try Data(contentsOf: jsonURL)
        } catch {
            throw ProjectPackageError.invalidJSON(error.localizedDescription)
        }

        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProjectPackageError.invalidJSON("根节点必须是对象")
            }
            object = parsed
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError.invalidJSON(error.localizedDescription)
        }

        let version = object["schemaVersion"] as? Int ?? -1
        guard supportedSchemaVersions.contains(version) else {
            throw ProjectPackageError.unsupportedSchema(version)
        }

        let draft: ProjectDraft
        do {
            draft = try JSONDecoder().decode(ProjectDraft.self, from: data)
        } catch {
            throw ProjectPackageError.invalidJSON(error.localizedDescription)
        }

        let known = Set(ProjectDraft.CodingKeys.allCases.map(\.rawValue))
        let ignored = object.keys.filter { !known.contains($0) }.sorted()
        var warnings: [String] = []
        if !ignored.isEmpty {
            warnings.append("未识别字段不参与求解：\(ignored.joined(separator: ", "))")
        }
        return ProjectPackageLoad(draft: draft, ignoredKeys: ignored, warnings: warnings)
    }

    private static func encode(_ draft: ProjectDraft) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(draft)
    }

    private static func rejectPrivateAbsolutePaths(in data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("/Users/") || text.contains("/Downloads/") {
            throw ProjectPackageError.containsPrivateAbsolutePath
        }
    }

    /// A `project.json` file uses its parent as the package root.
    private static func packageDirectory(from url: URL) -> URL {
        if url.lastPathComponent == projectFileName {
            return url.deletingLastPathComponent()
        }
        return url
    }
}
