import Foundation
import Testing
@testable import SimuCore

private func sampleProject() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try ProjectCodec(registry: .builtIn).decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
}

@Test func packageRoundTripPreservesProject() throws {
    let project = try sampleProject()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("demo.simunow")
    let codec = ProjectPackageCodec()
    try codec.write(project, to: package)
    #expect(try codec.load(from: package) == project)
    // Unknown sibling files are preserved across saves.
    let sibling = package.appendingPathComponent("notes.txt")
    try "keep".write(to: sibling, atomically: false, encoding: .utf8)
    var edited = project
    edited.name = "Renamed"
    try codec.write(edited, to: package)
    #expect(try codec.load(from: package) == edited)
    #expect(FileManager.default.fileExists(atPath: sibling.path))
}

@Test func packageLoadRejectsMissingAndCorruptFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let codec = ProjectPackageCodec()
    #expect(throws: ProjectPackageError.notAPackage("absent.simunow")) {
        try codec.load(from: directory.appendingPathComponent("absent.simunow"))
    }
    let empty = directory.appendingPathComponent("empty.simunow")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    #expect(throws: ProjectPackageError.missingProjectFile("project.json")) { try codec.load(from: empty) }
    let corrupt = directory.appendingPathComponent("corrupt.simunow")
    try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: corrupt.appendingPathComponent("project.json"))
    #expect(throws: ProjectPackageError.self) { try codec.load(from: corrupt) }
}

@Test func legacyDraftRequiresExplicitMigration() throws {
    let draft = ProjectDraft(name: "旧项目", spaceType: .classroom)
    let data = try JSONEncoder().encode(draft)
    let codec = ProjectPackageCodec()
    #expect(throws: ProjectPackageError.unsupportedVersion(1)) { try codec.decodeProject(data) }
    let migrated = try ProjectMigrator.migrate(data)
    #expect(migrated.project.geometry.rooms.isEmpty && migrated.project.scenarios.isEmpty)
    #expect(!migrated.notes.isEmpty)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = directory.appendingPathComponent("migrated.simunow")
    try codec.write(migrated.project, to: package)
    #expect(try codec.load(from: package) == migrated.project)
}
