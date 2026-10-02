import CryptoKit
import Foundation
import SimuCore
import SimuWorkspace
import Testing
import UniformTypeIdentifiers

private func packageFixture() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    var project = try ProjectCodec(registry: .builtIn).decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    // The wire fixture's artificial external reference is not a package asset.
    project.scenarios[0].inputs.environment.weather?.relativePath = "assets/weather/not-packaged.epw"
    return project
}

private func temporaryPackageDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SimuNow-package-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func packageWrapper(_ project: ProjectDocument, metadata: Data? = nil) throws -> FileWrapper {
    var entries = ["project.json": FileWrapper(regularFileWithContents: try ProjectCodec(registry: .builtIn).encode(project))]
    if let metadata { entries["metadata.json"] = FileWrapper(regularFileWithContents: metadata) }
    return FileWrapper(directoryWithFileWrappers: entries)
}

@Test func projectPackageDiskCloseReopenPreservesInputsAndOpaqueEntries() async throws {
    let directory = try temporaryPackageDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Office.simunow")
    var project = try packageFixture()
    let payload = try JSONValue(data: Data("{\"precision\":1.23456789012345678901234567890123456789,\"big\":123456789012345678901234567890,\"nested\":[null,true]}".utf8))
    project.scenarios[0].inputs.hvac[0].definition = .init(kind: "future.hvac", payloadVersion: 99, payload: payload)
    let bytes = Data([0, 255, 13, 10, 1])
    let metadata = ProjectPackageMetadata(baselineScenarioID: project.scenarios[0].id, templateID: "office", templateVersion: 1)
    let document = try SimuNowDocument(project: project, metadata: metadata, preservedEntries: [
        "assets": .directory(["room.usdz": .file(bytes)]),
        "runs": .directory(["old-run": .directory(["fields": .directory(["unknown.bin": .file(bytes)]), "empty": .directory([:])])]),
        "future.txt": .file(Data("keep me".utf8))
    ])
    let io = ProjectPackageIO()
    try await io.writePackage(document, to: url)
    let reopened = try await io.readPackage(from: url)
    #expect(reopened.project == project)
    #expect(reopened.metadata == metadata)
    #expect(reopened.preservedEntries == document.preservedEntries)
    #expect(reopened.project.scenarios[0].inputs.hvac[0].definition.payload == payload)
    #expect(!reopened.requiresRepair)
    #expect(reopened.integrityReport.issues.contains { $0.code == "weather_asset_missing" })
    if let exchange = ProcessInfo.processInfo.environment["SIMUNOW_CONTRACT_DIR"] {
        let metadataBytes = try #require(document.makeFileWrapper().fileWrappers?["metadata.json"]?.regularFileContents)
        try metadataBytes.write(to: URL(fileURLWithPath: exchange).appendingPathComponent("package.app-metadata.json"))
    }
    var renamed = reopened
    renamed.project.name = "Renamed"
    try await io.writePackage(renamed, to: url)
    let again = try await io.readPackage(from: url)
    #expect(again.project.name == "Renamed")
    #expect(again.preservedEntries == document.preservedEntries)
    // Launch Services loads conformance from the App's exported declaration;
    // the bare SwiftPM test executable has no application Info.plist.
    #expect(UTType.simuNowProject.identifier == "com.simunow.project")
}

@Test func projectPackageRejectsMissingMalformedAndFutureVersions() throws {
    let project = try packageFixture()
    #expect(throws: ProjectPackageError.missingRequiredFile("metadata.json")) { try SimuNowDocument(package: packageWrapper(project)) }
    for metadata in ["garbage", "{\"packageVersion\":1,\"packageVersion\":1}", "{\"packageVersion\":1,\"future\":true}", "{\"packageVersion\":1,\"templateID\":\"office\"}", "{\"packageVersion\":1,\"baselineScenarioID\":null}"] {
        #expect(throws: (any Error).self) { try SimuNowDocument(package: packageWrapper(project, metadata: Data(metadata.utf8))) }
    }
    #expect(throws: ProjectPackageError.unsupportedPackageVersion(2)) {
        try SimuNowDocument(package: packageWrapper(project, metadata: Data("{\"packageVersion\":2}".utf8)))
    }
    let meta = FileWrapper(regularFileWithContents: Data("{\"packageVersion\":1}".utf8))
    #expect(throws: ProjectPackageError.missingRequiredFile("project.json")) {
        try SimuNowDocument(package: FileWrapper(directoryWithFileWrappers: ["metadata.json": meta]))
    }
    var future = try JSONValue(data: ProjectCodec(registry: .builtIn).encode(project)).fields!
    future["schemaVersion"] = .number("3")
    #expect(throws: ProjectDataError.unsupportedVersion(3)) {
        try SimuNowDocument(package: FileWrapper(directoryWithFileWrappers: [
            "metadata.json": meta, "project.json": FileWrapper(regularFileWithContents: try JSONValue.object(future).data())
        ]))
    }
    #expect(throws: (any Error).self) {
        try SimuNowDocument(package: FileWrapper(directoryWithFileWrappers: ["metadata.json": meta, "project.json": FileWrapper(regularFileWithContents: Data("{".utf8))]))
    }
}

@Test func projectPackageRepairAndFailedSaveKeepOriginal() async throws {
    let directory = try temporaryPackageDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Office.simunow")
    let io = ProjectPackageIO()
    let original = try SimuNowDocument(project: packageFixture())
    try await io.writePackage(original, to: url)
    let originalJSON = try Data(contentsOf: url.appendingPathComponent("project.json"))
    var invalidProject = original.project
    invalidProject.geometry.rooms[0].northAngle = .known(value: 360, source: .init(kind: .user))
    var repair = try SimuNowDocument(project: invalidProject)
    #expect(repair.requiresRepair)
    do { try await io.writePackage(repair, to: url); Issue.record("Invalid input was saved") } catch {}
    #expect(try Data(contentsOf: url.appendingPathComponent("project.json")) == originalJSON)
    repair.project = original.project
    repair.metadata.baselineScenarioID = UUID()
    #expect(repair.requiresRepair)
    #expect(repair.integrityReport.issues.contains { $0.code == "baseline_reference" })
    repair.metadata.baselineScenarioID = nil
    #expect(!repair.requiresRepair)
    // A non-directory parent forces a filesystem failure after serialization.
    do { try await io.writePackage(repair, to: url.appendingPathComponent("project.json/impossible.simunow")); Issue.record("Filesystem failure was expected") } catch {}
    #expect(try Data(contentsOf: url.appendingPathComponent("project.json")) == originalJSON)
    #expect(try await io.readPackage(from: url).project == original.project)
    #expect(!SimuNowDocument.unfinished().requiresRepair)
    #expect(try SimuNowDocument.unfinished().makeFileWrapper().isDirectory)
}

@Test func projectJSONImportRequiresExplicitMigrationAndNeverRewritesSource() async throws {
    let directory = try temporaryPackageDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("legacy.json")
    let draft = ProjectDraft(name: "Legacy")
    let bytes = try JSONEncoder().encode(draft)
    try bytes.write(to: url)
    let io = ProjectPackageIO()
    do { _ = try await io.importJSON(from: url); Issue.record("Implicit migration occurred") }
    catch { #expect(error as? ProjectPackageError == .explicitMigrationRequired) }
    let migrated = try await io.importJSON(from: url, allowV1Migration: true)
    #expect(migrated.migratedFromV1)
    #expect(!migrated.notes.isEmpty)
    #expect(migrated.document.project.id == draft.id)
    #expect(migrated.document.project.geometry.rooms.isEmpty && migrated.document.project.scenarios.isEmpty)
    #expect(try Data(contentsOf: url) == bytes)
    let packageURL = directory.appendingPathComponent("Migrated.simunow")
    try await io.writePackage(migrated.document, to: packageURL)
    #expect(try await io.readPackage(from: packageURL).project == migrated.document.project)
    #expect(try Data(contentsOf: url) == bytes)
    let imported = try await io.importJSON(ProjectCodec(registry: .builtIn).encode(packageFixture()))
    #expect(!imported.migratedFromV1)
}

@Test func projectPackageImportBudgetAndSymlinksAreRejected() async throws {
    let directory = try temporaryPackageDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = ProjectDocument.unfinished(name: "Draft")
    let small = ProjectPackageLimits(maximumEntries: 2)
    #expect(throws: (any Error).self) { try SimuNowDocument(package: packageWrapper(project, metadata: Data("{\"packageVersion\":1}".utf8)), limits: small) }
    #expect(throws: (any Error).self) { try SimuNowDocument(project: project, preservedEntries: ["../outside": .file(Data())]) }
    let symlink = FileWrapper(symbolicLinkWithDestinationURL: directory)
    #expect(throws: (any Error).self) { try SimuNowDocument(package: symlink) }
    let external = directory.appendingPathComponent("outside.bin")
    try Data("outside".utf8).write(to: external)
    let packageURL = directory.appendingPathComponent("Draft.simunow")
    let io = ProjectPackageIO()
    try await io.writePackage(try SimuNowDocument(project: project), to: packageURL)
    try FileManager.default.createSymbolicLink(at: packageURL.appendingPathComponent("link"), withDestinationURL: external)
    do { _ = try await io.readPackage(from: packageURL); Issue.record("Symlink was accepted") } catch {}
    let limitIO = ProjectPackageIO(limits: .init(maximumProjectBytes: 2))
    do { _ = try await limitIO.importJSON(Data("{} ".utf8)); Issue.record("Oversize JSON was accepted") } catch {}
    let depth = ProjectPackageEntry.directory(["a": .directory(["b": .directory(["c": .file(Data())])])])
    #expect(throws: (any Error).self) {
        try SimuNowDocument(project: project, preservedEntries: ["deep": depth], limits: .init(maximumDepth: 2))
    }
}

@Test func weatherImportCopiesRelativeAssetAndChecksHash() async throws {
    let directory = try temporaryPackageDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("weather.epw")
    let bytes = Data("LOCATION,Test\nDESIGN CONDITIONS,0\nTYPICAL/EXTREME PERIODS,0\nGROUND TEMPERATURES,0\nHOLIDAYS/DAYLIGHT SAVINGS,No,0,0,0\nCOMMENTS 1,Test header only\nCOMMENTS 2,No physical validation claimed\nDATA PERIODS,1,1,Data,Sunday,1/1,12/31\n2026,1,1,1,60,data\n".utf8)
    try bytes.write(to: url)
    let io = ProjectPackageIO()
    let original = try SimuNowDocument(project: packageFixture(), preservedEntries: ["keep.bin": .file(Data([1,2]))])
    let document = try await io.importWeather(from: url, into: original, scenarioID: original.project.scenarios[0].id)
    let weather = try #require(document.project.scenarios[0].inputs.environment.weather)
    #expect(weather.relativePath.hasPrefix("assets/weather/"))
    #expect(!weather.relativePath.contains(directory.path))
    #expect(ProjectPackageEntry.directory(document.preservedEntries).entry(at: weather.relativePath) == .file(bytes))
    #expect(document.preservedEntries["keep.bin"] == original.preservedEntries["keep.bin"])
    #expect(!document.requiresRepair)
    var badHash = document
    badHash.project.scenarios[0].inputs.environment.weather?.sha256 = String(repeating: "0", count: 64)
    #expect(badHash.requiresRepair)
    #expect(badHash.integrityReport.issues.contains { $0.code == "weather_asset_hash" })
    try Data("arbitrary".utf8).write(to: url)
    do { _ = try await io.importWeather(from: url, into: original, scenarioID: original.project.scenarios[0].id); Issue.record("Non-EPW bytes accepted") } catch {}
}

@Test func projectPackageConstructionChecksCompleteOutputBudget() throws {
    let project = ProjectDocument.unfinished(name: "Draft")
    let projectBytes = try ProjectCodec(registry: .builtIn).encode(project)
    let metadataBytes = Data("{\"packageVersion\":1}".utf8)
    let total = projectBytes.count + metadataBytes.count
    // Root + project.json + metadata.json are three entries even without assets.
    let exact = try SimuNowDocument(project: project, limits: .init(maximumEntries: 3, maximumTotalBytes: total))
    #expect(try exact.makeFileWrapper().fileWrappers?.count == 2)
    #expect(throws: (any Error).self) {
        try SimuNowDocument(project: project, limits: .init(maximumEntries: 2))
    }
    #expect(throws: (any Error).self) {
        try SimuNowDocument(project: project, limits: .init(maximumTotalBytes: total - 1))
    }
    #expect(throws: (any Error).self) {
        try SimuNowDocument(project: project, limits: .init(maximumProjectBytes: projectBytes.count - 1))
    }
    #expect(throws: (any Error).self) {
        try SimuNowDocument(project: project, limits: .init(maximumMetadataBytes: metadataBytes.count - 1))
    }
    var repairProject = try packageFixture()
    repairProject.geometry.rooms[0].northAngle = .known(value: 360, source: .init(kind: .user))
    #expect(try SimuNowDocument(project: repairProject).requiresRepair)
}

@Test func weatherImportRejectsUnsavableCompletePackageBeforeCommit() async throws {
    let directory = try temporaryPackageDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("weather.epw")
    let data = Data("LOCATION,Test\nDESIGN CONDITIONS,0\nTYPICAL/EXTREME PERIODS,0\nGROUND TEMPERATURES,0\nHOLIDAYS/DAYLIGHT SAVINGS,No,0,0,0\nCOMMENTS 1,Header fixture\nCOMMENTS 2,No physical validity claimed\nDATA PERIODS,1,1,Data,Sunday,1/1,12/31\n2026,1,1,1,60,data\n".utf8)
    try data.write(to: url)
    let project = try packageFixture()
    let io = ProjectPackageIO()
    // The asset tree uses four entries, but the complete tree uses six.
    let entryLimited = try SimuNowDocument(project: project, limits: .init(maximumEntries: 5))
    do {
        _ = try await io.importWeather(from: url, into: entryLimited, scenarioID: project.scenarios[0].id)
        Issue.record("An import exceeding the complete entry budget was accepted")
    } catch { #expect(error is ProjectPackageError) }
    let full = try await io.importWeather(from: url, into: SimuNowDocument(project: project), scenarioID: project.scenarios[0].id)
    let completeBytes = try ProjectCodec(registry: .builtIn).encode(full.project).count
        + Data("{\"packageVersion\":1}".utf8).count + data.count
    let byteLimited = try SimuNowDocument(project: project, limits: .init(maximumTotalBytes: completeBytes - 1))
    do {
        _ = try await io.importWeather(from: url, into: byteLimited, scenarioID: project.scenarios[0].id)
        Issue.record("An import exceeding the complete byte budget was accepted")
    } catch { #expect(error is ProjectPackageError) }
    #expect(entryLimited.preservedEntries.isEmpty && byteLimited.preservedEntries.isEmpty)
    let exact = try SimuNowDocument(project: project, limits: .init(maximumEntries: 6, maximumTotalBytes: completeBytes))
    let imported = try await io.importWeather(from: url, into: exact, scenarioID: project.scenarios[0].id)
    #expect(try imported.makeFileWrapper().isDirectory)
}
