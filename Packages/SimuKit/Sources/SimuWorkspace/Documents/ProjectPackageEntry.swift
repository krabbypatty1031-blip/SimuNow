import Foundation

/// A value tree crosses actor boundaries; Foundation FileWrapper never does.
public indirect enum ProjectPackageEntry: Equatable, Sendable {
    case file(Data)
    case directory([String: ProjectPackageEntry])

    public func entry(at relativePath: String) -> ProjectPackageEntry? {
        var entry = self
        for part in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
            guard Self.validName(String(part)), case .directory(let children) = entry,
                  let next = children[String(part)] else { return nil }
            entry = next
        }
        return entry
    }

    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." &&
        !name.contains("/") && !name.contains("\\") && !name.contains(":") && !name.contains("\0")
    }

    func fileWrapper() -> FileWrapper {
        switch self {
        case .file(let data): return FileWrapper(regularFileWithContents: data)
        case .directory(let entries): return FileWrapper(directoryWithFileWrappers: entries.mapValues { $0.fileWrapper() })
        }
    }

    static func capture(_ wrapper: FileWrapper, budget: inout PackageBudget, depth: Int = 0) throws -> Self {
        try budget.addEntry(depth: depth)
        if wrapper.isSymbolicLink { throw ProjectPackageError.invalidPackage("不接受符号链接。") }
        if wrapper.isRegularFile, let data = wrapper.regularFileContents {
            try budget.addBytes(data.count)
            return .file(data)
        }
        guard wrapper.isDirectory, let files = wrapper.fileWrappers else {
            throw ProjectPackageError.invalidPackage("条目必须是普通文件或目录。")
        }
        guard files.count <= budget.remainingEntries else { throw ProjectPackageError.resourceLimit("文件数量过多。") }
        var entries: [String: Self] = [:]
        for (name, child) in files {
            guard validName(name) else { throw ProjectPackageError.invalidPackage("条目名称不是安全的相对路径。") }
            entries[name] = try capture(child, budget: &budget, depth: depth + 1)
        }
        return .directory(entries)
    }

    func validate(budget: inout PackageBudget, depth: Int = 0) throws {
        try budget.addEntry(depth: depth)
        switch self {
        case .file(let data): try budget.addBytes(data.count)
        case .directory(let entries):
            guard entries.count <= budget.remainingEntries else { throw ProjectPackageError.resourceLimit("文件数量过多。") }
            for (name, entry) in entries {
                guard Self.validName(name) else { throw ProjectPackageError.invalidPackage("条目名称不是安全的相对路径。") }
                try entry.validate(budget: &budget, depth: depth + 1)
            }
        }
    }
}

struct PackageBudget {
    let limits: ProjectPackageLimits
    private var entries = 0
    private var bytes = 0
    var remainingEntries: Int { max(0, limits.maximumEntries - entries) }
    var remainingBytes: Int { max(0, limits.maximumTotalBytes - bytes) }

    init(_ limits: ProjectPackageLimits) { self.limits = limits }
    mutating func addEntry(depth: Int) throws {
        guard depth <= limits.maximumDepth, entries < limits.maximumEntries else {
            throw ProjectPackageError.resourceLimit("目录过深或文件数量过多。")
        }
        entries += 1
    }
    mutating func addBytes(_ count: Int) throws {
        guard count <= limits.maximumFileBytes, count <= limits.maximumTotalBytes - bytes else {
            throw ProjectPackageError.resourceLimit("单个文件或项目总大小过大。")
        }
        bytes += count
    }
}
