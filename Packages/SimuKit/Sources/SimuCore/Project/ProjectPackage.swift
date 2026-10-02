import Foundation

/// Errors opening a `.simunow` package. Migration of v1 drafts is a separate explicit step (ProjectMigrator).
public enum ProjectPackageError: Error, Equatable, Sendable {
    case notAPackage(String)
    case missingProjectFile(String)
    case corruptProject(String)
    case unsupportedVersion(Int)
}

/// A `.simunow` package is a directory containing `project.json` (ProjectDocument v2 wire JSON).
/// Runs, measurements and field data extend the package in later phases; unknown sibling files are preserved.
public struct ProjectPackageCodec: Sendable {
    public static let projectFileName = "project.json"
    public static let packageExtension = "simunow"

    public let codec: ProjectCodec
    public init(registry: ModelRegistry = .builtIn) {
        self.codec = ProjectCodec(registry: registry)
    }

    /// Atomic save: write to a sibling temporary file, then replace. Never leaves a half-written project.json.
    public func write(_ project: ProjectDocument, to packageURL: URL) throws {
        let data = try codec.encode(project)
        let manager = FileManager.default
        var isDirectory = ObjCBool(false)
        if !manager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory) {
            try manager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        } else if !isDirectory.boolValue {
            throw ProjectPackageError.notAPackage(packageURL.lastPathComponent)
        }
        let target = packageURL.appendingPathComponent(Self.projectFileName)
        try data.write(to: target, options: .atomic)
    }

    public func load(from packageURL: URL) throws -> ProjectDocument {
        let manager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard manager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectPackageError.notAPackage(packageURL.lastPathComponent)
        }
        let projectURL = packageURL.appendingPathComponent(Self.projectFileName)
        guard let data = manager.contents(atPath: projectURL.path) else {
            throw ProjectPackageError.missingProjectFile(Self.projectFileName)
        }
        return try decodeProject(data)
    }

    public func decodeProject(_ data: Data) throws -> ProjectDocument {
        do {
            return try codec.decode(data)
        } catch ProjectDataError.unsupportedVersion(let version) {
            throw ProjectPackageError.unsupportedVersion(version)
        } catch let error as ProjectDataError {
            throw ProjectPackageError.corruptProject("\(error)")
        }
    }
}
