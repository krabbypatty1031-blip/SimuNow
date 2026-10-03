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
    // The test runner is not sandboxed, so the shell-style X_OK check is a
    // stand-in for "the pinned engines tree exists"; isConfigured itself must
    // keep reading POSIX bits (see hasExecuteBitUsesPosixBitsNotAccessXOK).
    if LocalEngineProbe.hasExecuteBit(at: LocalEngineProbe.energyPlusURL(in: engines).path) {
        #expect(LocalEngineProbe.isConfigured(repositoryRoot: repo, enginesRoot: engines))
        #expect(!LocalEngineProbe.isConfigured(repositoryRoot: engines, enginesRoot: engines))
    }
}

@Test func hasExecuteBitUsesPosixBitsNotAccessXOK() throws {
    // Regression anchor (2026-10-03 hand test): App Sandbox denies access(X_OK)
    // for staged container paths and user-selected engine directories alike,
    // so `isExecutableFile` probes returned false in-app while `test -x`
    // passed in a shell. The probe must stat the file and read the execute
    // bits; this test fixes that stat semantics outside the sandbox.
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-xbit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // 0o755 carries the execute bits -> probe true.
    let executable = dir.appendingPathComponent("engine.sh")
    try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    #expect(LocalEngineProbe.hasExecuteBit(at: executable.path))

    // 0o644 has no execute bits -> probe false even though the file exists.
    let plain = dir.appendingPathComponent("notes.txt")
    try "plain text".write(to: plain, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)
    #expect(!LocalEngineProbe.hasExecuteBit(at: plain.path))

    // stat follows symlinks: the staged layout is `energyplus -> energyplus-25.2.0`,
    // so the link probes the target's bits.
    let link = dir.appendingPathComponent("energyplus")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
    #expect(LocalEngineProbe.hasExecuteBit(at: link.path))

    // A missing path is not executable; the caller reports it as unconfigured.
    #expect(!LocalEngineProbe.hasExecuteBit(at: dir.appendingPathComponent("missing").path))
}

@Test func isConfiguredAcceptsPosixExecBitWithoutXOKProbe() throws {
    // Regression anchor: build a repo + engines tree whose binary has the
    // execute bits but was never probed through access(X_OK). isConfigured
    // must accept it on POSIX bits alone, which is what the sandboxed app
    // needs for its staged copies.
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = root.appendingPathComponent("repo", isDirectory: true)
    let engines = root.appendingPathComponent("engines", isDirectory: true)
    try FileManager.default.createDirectory(
        at: repo.appendingPathComponent("Backend/src/simunow_worker", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: engines.appendingPathComponent("EnergyPlus", isDirectory: true),
        withIntermediateDirectories: true
    )
    // Worker presence + binary with 0o755 bits -> configured.
    try "# worker stub".write(
        to: repo.appendingPathComponent("Backend/src/simunow_worker/__main__.py"),
        atomically: true, encoding: .utf8
    )
    let binary = engines.appendingPathComponent("EnergyPlus/energyplus")
    try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    #expect(LocalEngineProbe.isConfigured(repositoryRoot: repo, enginesRoot: engines))

    // Drop the execute bits -> unconfigured; no invented engine readiness.
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binary.path)
    #expect(!LocalEngineProbe.isConfigured(repositoryRoot: repo, enginesRoot: engines))
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
