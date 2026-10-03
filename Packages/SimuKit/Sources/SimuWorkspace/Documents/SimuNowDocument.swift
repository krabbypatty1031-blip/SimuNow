import CryptoKit
import Foundation
import SimuCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    public static let simuNowProject = UTType(exportedAs: "com.simunow.project", conformingTo: .package)
}

/// The DocumentGroup binding owns persisted state. Editors commit complete values
/// to this document; selection and undo UI are not part of the package.
public struct SimuNowDocument: FileDocument, Sendable {
    public static var readableContentTypes: [UTType] { [.simuNowProject] }
    public static var writableContentTypes: [UTType] { [.simuNowProject] }

    public var project: ProjectDocument
    public var metadata: ProjectPackageMetadata
    /// Transient change token, never written to project metadata. Sidefile readers reload off MainActor.
    public private(set) var nativeSidefileRevision = UUID()
    public private(set) var preservedEntries: [String: ProjectPackageEntry]
    private let registry: ModelRegistry
    private let limits: ProjectPackageLimits
    private let weatherAssetHashes: [String: String]
    // Public project/metadata values may be edited by a caller. Cached bytes are
    // reusable only when these immutable validated baseline values still match.
    private let validatedProject: ProjectDocument
    private let validatedProjectData: Data
    private let validatedMetadata: ProjectPackageMetadata
    private let validatedMetadataData: Data

    public init(
        project: ProjectDocument, metadata: ProjectPackageMetadata = .init(),
        preservedEntries: [String: ProjectPackageEntry] = [:],
        registry: ModelRegistry = .builtIn, limits: ProjectPackageLimits = .standard
    ) throws {
        self.project = project
        self.metadata = metadata
        self.preservedEntries = preservedEntries
        self.registry = registry
        self.limits = limits
        try limits.validate()
        let projectData = try ProjectCodec(registry: registry).encode(project)
        let metadataData = try metadata.encoded()
        self.validatedProject = project
        self.validatedProjectData = projectData
        self.validatedMetadata = metadata
        self.validatedMetadataData = metadataData
        guard projectData.count <= limits.maximumProjectBytes,
            metadataData.count <= limits.maximumMetadataBytes
        else {
            throw ProjectPackageError.resourceLimit("项目或元数据过大。")
        }
        guard preservedEntries["project.json"] == nil, preservedEntries["metadata.json"] == nil else {
            throw ProjectPackageError.invalidPackage("保留条目不能覆盖项目或元数据。")
        }
        // Validate the complete output before imports become editor state. Opaque
        // attachments alone can fit while the required JSON files push the package
        // beyond its byte or entry budget. This structural/capacity check deliberately
        // accepts semantic repair projects, which remain blocked by the save gate.
        var outputEntries = preservedEntries
        outputEntries["project.json"] = .file(projectData)
        outputEntries["metadata.json"] = .file(metadataData)
        var budget = PackageBudget(limits)
        try ProjectPackageEntry.directory(outputEntries).validate(budget: &budget)
        let tree = ProjectPackageEntry.directory(preservedEntries)
        var hashes: [String: String] = [:]
        for scenario in project.scenarios {
            guard let path = scenario.inputs.environment.weather?.relativePath,
                hashes[path] == nil, case .file(let data) = tree.entry(at: path)
            else { continue }
            hashes[path] = Self.contentHash(data)
        }
        self.weatherAssetHashes = hashes
    }

    public static func unfinished(name: String = "未命名项目") -> Self {
        // The built-in empty project has no speculative physical defaults.
        do { return try Self(project: .unfinished(name: name)) } catch {
            preconditionFailure("Built-in unfinished project violates its contract: \(error)")
        }
    }

    public init(configuration: ReadConfiguration) throws {
        try self.init(package: configuration.file)
    }

    public init(
        package: FileWrapper, registry: ModelRegistry = .builtIn,
        limits: ProjectPackageLimits = .standard
    ) throws {
        var budget = PackageBudget(limits)
        let tree = try ProjectPackageEntry.capture(package, budget: &budget)
        try self.init(packageTree: tree, registry: registry, limits: limits)
    }

    init(packageTree: ProjectPackageEntry, registry: ModelRegistry, limits: ProjectPackageLimits) throws {
        guard case .directory(var entries) = packageTree else {
            throw ProjectPackageError.invalidPackage(".simunow 必须是项目包目录，JSON 请使用导入。")
        }
        func requiredData(_ name: String, maximum: Int) throws -> Data {
            guard let entry = entries[name] else { throw ProjectPackageError.missingRequiredFile(name) }
            guard case .file(let data) = entry else {
                throw ProjectPackageError.invalidPackage("\(name) 必须是普通文件。")
            }
            guard data.count <= maximum else { throw ProjectPackageError.resourceLimit("\(name) 过大。") }
            return data
        }
        let metadata = try ProjectPackageMetadata.decode(
            requiredData("metadata.json", maximum: limits.maximumMetadataBytes))
        let project = try ProjectCodec(registry: registry).decode(
            requiredData("project.json", maximum: limits.maximumProjectBytes))
        entries.removeValue(forKey: "project.json")
        entries.removeValue(forKey: "metadata.json")
        try self.init(
            project: project, metadata: metadata, preservedEntries: entries, registry: registry,
            limits: limits)
    }

    /// Recomputed after edits, so repair/save state cannot become stale.
    public var integrityReport: ValidationReport {
        var issues: [ValidationIssue]
        do { issues = try ProjectValidator().validate(project, registry: registry).issues } catch {
            issues = [.init(code: "project_contract", path: "", message: "项目结构或已知类型无效：\(error)")]
        }
        do { try metadata.validate() } catch {
            issues.append(
                .init(code: "package_metadata", path: "/metadata", message: error.localizedDescription))
        }
        if let id = metadata.baselineScenarioID, !project.scenarios.contains(where: { $0.id == id }) {
            issues.append(
                .init(
                    code: "baseline_reference", path: "/metadata/baselineScenarioID", entityID: id,
                    message: "基准方案已不存在，请选择有效方案。"))
        }
        let assets = ProjectPackageEntry.directory(preservedEntries)
        for (index, scenario) in project.scenarios.enumerated() {
            guard let weather = scenario.inputs.environment.weather else { continue }
            let path = "/scenarios/\(index)/inputs/environment/weather"
            guard weather.relativePath.hasPrefix("assets/"),
                weather.relativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                    ProjectPackageEntry.validName(String($0))
                })
            else {
                issues.append(
                    .init(
                        code: "weather_asset_path", path: path + "/relativePath", entityID: scenario.id,
                        message: "天气资源必须使用 assets/ 内的项目包相对路径。"))
                continue
            }
            guard let entry = assets.entry(at: weather.relativePath) else {
                issues.append(
                    .init(
                        code: "weather_asset_missing", path: path + "/relativePath", entityID: scenario.id,
                        blocks: [.inputPreparation], message: "项目包未包含该天气资源，补充前不能计算。"))
                continue
            }
            guard case .file(let data) = entry else {
                issues.append(
                    .init(
                        code: "weather_asset_file", path: path + "/relativePath", entityID: scenario.id,
                        message: "天气资源引用必须指向普通文件。"))
                continue
            }
            // Assets are immutable. Reuse the digest captured during background
            // load/import so ordinary UI validation does not rehash EPW bytes.
            let hash = weatherAssetHashes[weather.relativePath] ?? Self.contentHash(data)
            if hash != weather.sha256.lowercased() {
                issues.append(
                    .init(
                        code: "weather_asset_hash", path: path + "/sha256", entityID: scenario.id,
                        message: "天气资源内容与声明的 SHA-256 不一致。"))
            }
        }
        return ValidationReport(issues: issues)
    }

    public var requiresRepair: Bool { !integrityReport.passes(.projectIntegrity) }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try makeFileWrapper()
    }

    /// For independent exports/tests. DocumentGroup itself manages coordinated saves.
    public func makeFileWrapper() throws -> FileWrapper {
        let report = integrityReport
        let blocking = report.issues.filter { $0.blocks.contains(.projectIntegrity) }
        guard blocking.isEmpty else { throw ProjectPackageError.repairRequired(blocking) }
        let data = try ProjectCodec(registry: registry).encode(project)
        let metadataData = try metadata.encoded()
        guard data.count <= limits.maximumProjectBytes, metadataData.count <= limits.maximumMetadataBytes
        else {
            throw ProjectPackageError.resourceLimit("项目或元数据过大。")
        }
        var entries = preservedEntries
        entries["project.json"] = .file(data)
        entries["metadata.json"] = .file(metadataData)
        let tree = ProjectPackageEntry.directory(entries)
        var budget = PackageBudget(limits)
        try tree.validate(budget: &budget)
        return tree.fileWrapper()
    }

    func addingWeatherAsset(_ data: Data, name: String, scenarioID: UUID, hash: String) throws -> Self {
        guard project.scenarios.filter({ $0.id == scenarioID }).count == 1,
            let index = project.scenarios.firstIndex(where: { $0.id == scenarioID })
        else {
            throw ProjectDataError.missingScenario(scenarioID)
        }
        var entries = preservedEntries
        var assets: [String: ProjectPackageEntry] = [:]
        if let entry = entries["assets"] {
            guard case .directory(let existing) = entry else {
                throw ProjectPackageError.invalidPackage("assets 已被普通文件占用。")
            }
            assets = existing
        }
        var weather: [String: ProjectPackageEntry] = [:]
        if let entry = assets["weather"] {
            guard case .directory(let existing) = entry else {
                throw ProjectPackageError.invalidPackage("assets/weather 已被普通文件占用。")
            }
            weather = existing
        }
        weather[name] = .file(data)
        assets["weather"] = .directory(weather)
        entries["assets"] = .directory(assets)
        var updated = project
        updated.scenarios[index].inputs.environment.weather = .init(
            relativePath: "assets/weather/\(name)", sha256: hash)
        return try Self(
            project: updated, metadata: metadata, preservedEntries: entries, registry: registry,
            limits: limits)
    }

    func replacingNativeInputState(
        project: ProjectDocument, metadata: ProjectPackageMetadata, entries: [String: ProjectPackageEntry]
    ) throws -> Self {
        var next = try Self(
            project: project, metadata: metadata, preservedEntries: entries, registry: registry,
            limits: limits)
        if entries == preservedEntries { next.nativeSidefileRevision = nativeSidefileRevision }
        return next
    }

    func replacingPreservedEntries(_ entries: [String: ProjectPackageEntry]) throws -> Self {
        if entries == preservedEntries { return self }
        guard project == validatedProject, metadata == validatedMetadata,
            entries["assets"] == preservedEntries["assets"]
        else {
            // Caller changed public input or asset bytes: use the full constructor.
            return try Self(
                project: project, metadata: metadata, preservedEntries: entries,
                registry: registry, limits: limits)
        }
        guard entries["project.json"] == nil, entries["metadata.json"] == nil else {
            throw ProjectPackageError.invalidPackage("保留条目不能覆盖项目或元数据。")
        }
        var output = entries
        output["project.json"] = .file(validatedProjectData)
        output["metadata.json"] = .file(validatedMetadataData)
        var budget = PackageBudget(limits)
        try ProjectPackageEntry.directory(output).validate(budget: &budget)
        // Native append changes no project, metadata or weather source. Reuse
        // their verified bytes/digests, but still check the whole output budget.
        var next = self
        next.preservedEntries = entries
        next.nativeSidefileRevision = UUID()
        return next
    }

    private static func contentHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
