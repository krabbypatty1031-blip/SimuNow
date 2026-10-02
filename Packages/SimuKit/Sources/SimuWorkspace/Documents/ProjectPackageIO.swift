import CryptoKit
import Foundation
import SimuCore

public struct ProjectImportResult: Sendable {
    public let document: SimuNowDocument
    public let notes: [String]
    public let migratedFromV1: Bool

    public init(document: SimuNowDocument, notes: [String] = [], migratedFromV1: Bool = false) {
        self.document = document; self.notes = notes; self.migratedFromV1 = migratedFromV1
    }
}

/// Independent imports/exports run off MainActor. Only value documents cross this
/// actor; wrappers, handles, coordinators, and scoped URL access remain inside it.
public actor ProjectPackageIO {
    public let registry: ModelRegistry
    public let limits: ProjectPackageLimits

    public init(registry: ModelRegistry = .builtIn, limits: ProjectPackageLimits = .standard) {
        self.registry = registry; self.limits = limits
    }

    public func readPackage(from url: URL) throws -> SimuNowDocument {
        try limits.validate()
        try validateFileURL(url)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try coordinatedRead(url) { coordinatedURL in
            var budget = PackageBudget(limits)
            let tree = try readEntry(coordinatedURL, budget: &budget)
            return try SimuNowDocument(packageTree: tree, registry: registry, limits: limits)
        }
    }

    /// Explicit JSON import produces a new package document; it never writes the
    /// source URL. v1 is accepted only when the caller requests migration.
    public func importJSON(from url: URL, allowV1Migration: Bool = false) throws -> ProjectImportResult {
        try limits.validate()
        try validateFileURL(url)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try coordinatedRead(url) { coordinatedURL in
            try readFile(coordinatedURL, maximum: limits.maximumProjectBytes)
        }
        return try importJSON(data, allowV1Migration: allowV1Migration)
    }

    public func importJSON(_ data: Data, allowV1Migration: Bool = false) throws -> ProjectImportResult {
        try limits.validate()
        guard data.count <= limits.maximumProjectBytes else { throw ProjectPackageError.resourceLimit("项目 JSON 过大。") }
        let tree = try JSONValue(data: data)
        if tree["schemaVersion"]?.double == 1 {
            guard allowV1Migration else { throw ProjectPackageError.explicitMigrationRequired }
            let migration = try ProjectMigrator.migrate(data)
            return try .init(document: SimuNowDocument(project: migration.project, registry: registry, limits: limits),
                             notes: ["已将 v1 草稿迁移为新项目；原文件没有改写。房间与方案仍需补充。"] + migration.notes,
                             migratedFromV1: true)
        }
        return try .init(document: SimuNowDocument(project: ProjectCodec(registry: registry).decode(data),
                                                  registry: registry, limits: limits))
    }

    /// Copies a user-selected EPW into the package. Header checks identify the file
    /// format only; numerical validity and adapter suitability remain P3 work.
    public func importWeather(from url: URL, into document: SimuNowDocument, scenarioID: UUID) throws -> SimuNowDocument {
        try limits.validate()
        try validateFileURL(url)
        guard url.pathExtension.lowercased() == "epw" else { throw ProjectPackageError.invalidPackage("请选择 .epw 天气文件。") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try coordinatedRead(url) { target in try readFile(target, maximum: min(limits.maximumFileBytes, 16 * 1_024 * 1_024)) }
        guard let text = String(data: data, encoding: .utf8) else { throw ProjectPackageError.invalidPackage("EPW 文件须为 UTF-8 文本。") }
        let header = text.split(separator: "\n", maxSplits: 8, omittingEmptySubsequences: false)
        guard header.count == 9, header[0].hasPrefix("LOCATION,"), header[7].hasPrefix("DATA PERIODS,"),
              !header[8].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectPackageError.invalidPackage("文件缺少 EPW LOCATION、DATA PERIODS 或天气记录。")
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try document.addingWeatherAsset(data, name: hash + ".epw", scenarioID: scenarioID, hash: hash)
    }

    /// Independent exports only. Do not call this for a DocumentGroup-owned URL.
    /// Validation and serialization complete before the atomic write begins.
    public func writePackage(_ document: SimuNowDocument, to url: URL) throws {
        try validateFileURL(url)
        let wrapper = try document.makeFileWrapper()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            result = Result { try wrapper.write(to: target, options: [.atomic], originalContentsURL: nil) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProjectPackageError.invalidPackage("无法协调项目包写入。") }
        try result.get()
    }

    private func validateFileURL(_ url: URL) throws {
        guard url.isFileURL else { throw ProjectPackageError.invalidPackage("只能导入本地或文件提供器的文件 URL。") }
    }

    private func coordinatedRead<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges],
                                       error: &coordinationError) { target in
            result = Result { try operation(target) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProjectPackageError.invalidPackage("无法协调项目包读取。") }
        return try result.get()
    }

    private func readFile(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ProjectPackageError.invalidPackage("不接受符号链接或特殊文件。")
        }
        guard let size = values.fileSize, size <= maximum else {
            throw ProjectPackageError.resourceLimit("文件大小超出上限。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // A bounded read also covers a file growing after its size was inspected.
        var data = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1_024, maximum - data.count + 1)), !chunk.isEmpty {
            guard chunk.count <= maximum - data.count else { throw ProjectPackageError.resourceLimit("文件大小超出上限。") }
            data.append(chunk)
        }
        return data
    }

    private func readEntry(_ url: URL, budget: inout PackageBudget, depth: Int = 0) throws -> ProjectPackageEntry {
        try budget.addEntry(depth: depth)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw ProjectPackageError.invalidPackage("不接受符号链接。") }
        if values.isRegularFile == true {
            let maximum = min(limits.maximumFileBytes, budget.remainingBytes)
            let data = try readFile(url, maximum: maximum)
            try budget.addBytes(data.count)
            return .file(data)
        }
        guard values.isDirectory == true else { throw ProjectPackageError.invalidPackage("不接受特殊文件。") }
        // Enumerate lazily, one directory at a time: a malicious directory cannot
        // force an unbounded URL array before the entry budget is checked.
        var enumerationError: (any Error)?
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                           options: .skipsSubdirectoryDescendants,
                                                           errorHandler: { _, error in enumerationError = error; return false }) else {
            throw ProjectPackageError.invalidPackage("无法读取目录。")
        }
        var entries: [String: ProjectPackageEntry] = [:]
        while let child = iterator.nextObject() as? URL {
            let name = child.lastPathComponent
            guard ProjectPackageEntry.validName(name) else { throw ProjectPackageError.invalidPackage("条目名称不是安全的相对路径。") }
            entries[name] = try readEntry(child, budget: &budget, depth: depth + 1)
        }
        if let enumerationError { throw enumerationError }
        return .directory(entries)
    }
}
