import Foundation
import Testing
@testable import SimuCore

@Test func savingThenLoadingOfficePackagePreservesIdentityAndGeometry() throws {
    let source = try Data(contentsOf: fixturesDirectory().appendingPathComponent("project-v2-office.json"))
    let original = try JSONDecoder().decode(ProjectDraft.self, from: source)
    let package = try uniqueTempPackage()
    defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }

    try ProjectPackage.save(original, to: package)
    let loaded = try ProjectPackage.load(from: package)

    #expect(loaded.draft == original)
    #expect(loaded.draft.id == original.id)
    #expect(loaded.draft.hasCompletePhysicalModel)
    #expect(loaded.draft.geometry?.sizeX.value == 6)
    #expect(loaded.warnings.contains(where: { $0.contains("未识别字段不参与求解") }) == false)
}

@Test func loadingV1PackageDoesNotInventARoom() throws {
    let source = try Data(contentsOf: fixturesDirectory().appendingPathComponent("project-draft-v1.json"))
    let original = try JSONDecoder().decode(ProjectDraft.self, from: source)
    let package = try uniqueTempPackage()
    defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }

    try ProjectPackage.save(original, to: package)
    let loaded = try ProjectPackage.load(from: package)
    #expect(loaded.draft.schemaVersion == 1)
    #expect(loaded.draft.hasCompletePhysicalModel == false)
    #expect(loaded.draft.geometry == nil)
}

@Test func failedReplaceLeavesPreviousProjectJSONReadable() throws {
    let package = try uniqueTempPackage()
    defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
    let first = ProjectDraft(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "旧包"
    )
    try ProjectPackage.save(first, to: package)

    let next = ProjectDraft(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "新包"
    )
    #expect(throws: ProjectPackageError.self) {
        try ProjectPackage.save(next, to: package, replaceItem: { _, _ in
            throw ProjectPackageError.incompleteWrite
        })
    }
    let loaded = try ProjectPackage.load(from: package)
    #expect(loaded.draft.id == first.id)
    #expect(loaded.draft.name == "旧包")
}

@Test func missingOrInvalidPackageReturnsStructuredRecovery() throws {
    let empty = try uniqueTempPackage()
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty.deletingLastPathComponent()) }

    let missing = ProjectPackageError.missingProjectJSON
    #expect(throws: missing) {
        try ProjectPackage.load(from: empty)
    }
    #expect(missing.recoverySuggestion?.contains("project.json") == true)

    let invalid = empty.appendingPathComponent("project.json")
    try Data("not-json".utf8).write(to: invalid)
    do {
        _ = try ProjectPackage.load(from: empty)
        Issue.record("invalid JSON must not decode")
    } catch let error as ProjectPackageError {
        #expect(error.recoverySuggestion?.contains("重新导出") == true || error.recoverySuggestion?.contains("project.json") == true)
    }

    let unknown = empty.appendingPathComponent("project.json")
    try Data(#"{ "schemaVersion": 99, "id": "11111111-1111-1111-1111-111111111111", "name": "x", "spaceType": "office", "lengthUnit": "m", "coordinateSystem": "rightHandedZUp" }"#.utf8).write(to: unknown)
    do {
        _ = try ProjectPackage.load(from: empty)
        Issue.record("unknown schema must not load as solvable")
    } catch let error as ProjectPackageError {
        #expect(error.recoverySuggestion?.contains("schemaVersion") == true)
    }
}

@Test func loadIgnoresUnknownKeysAndDoesNotTreatThemAsSolvableInput() throws {
    let package = try uniqueTempPackage()
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
    let json = """
    {
      "schemaVersion": 1,
      "id": "11111111-1111-1111-1111-111111111111",
      "name": "办公室",
      "spaceType": "office",
      "lengthUnit": "m",
      "coordinateSystem": "rightHandedZUp",
      "futureOptional": true
    }
    """
    try Data(json.utf8).write(to: package.appendingPathComponent("project.json"))
    let loaded = try ProjectPackage.load(from: package)
    #expect(loaded.draft.hasCompletePhysicalModel == false)
    #expect(loaded.ignoredKeys.contains("futureOptional"))
    #expect(loaded.warnings.contains { $0.contains("未识别字段不参与求解") })
}

@Test func savedPackageJSONDoesNotEmbedPrivateAbsolutePaths() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    draft.geometry?.sizeX.reference = "/Users/krabbypatty/Downloads/secret.txt"
    let package = try uniqueTempPackage()
    defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
    #expect(throws: ProjectPackageError.containsPrivateAbsolutePath) {
        try ProjectPackage.save(draft, to: package)
    }
    #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("project.json").path) == false)
}

private func fixturesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
}

private func uniqueTempPackage() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p2-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("Room.simunow", isDirectory: true)
}
