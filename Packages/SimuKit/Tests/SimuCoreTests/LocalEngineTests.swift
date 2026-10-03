import Foundation
import Testing
import SimuSimulation

@Test func missingWorkerAndBinaryAreNotConfigured() {
    let empty = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-empty-engines-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    #expect(!LocalEngineProbe.isConfigured(repositoryRoot: empty, enginesRoot: empty))
}

@Test func pinnedRepositoryAndEnginesAreConfiguredWhenPresent() {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let engines = repo.appendingPathComponent("test/engines")
    if FileManager.default.isExecutableFile(atPath: LocalEngineProbe.energyPlusURL(in: engines).path) {
        #expect(LocalEngineProbe.isConfigured(repositoryRoot: repo, enginesRoot: engines))
        #expect(!LocalEngineProbe.isConfigured(repositoryRoot: engines, enginesRoot: engines))
    }
}

@Test func macSandboxEntitlementStaysEnabled() throws {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let text = try String(
        contentsOf: repo.appendingPathComponent("Apps/SimuNowMac/SimuNowMac.entitlements"),
        encoding: .utf8
    )
    #expect(text.contains("com.apple.security.app-sandbox"))
    #expect(text.contains("<true/>"))
    #expect(text.contains("com.apple.security.files.bookmarks.app-scope"))
    #expect(text.contains("com.apple.security.cs.disable-library-validation"))
    #expect(text.contains("com.apple.security.app-sandbox"))
    #expect(!text.contains("com.apple.security.app-sandbox</key>\n    <false/>"))
}
