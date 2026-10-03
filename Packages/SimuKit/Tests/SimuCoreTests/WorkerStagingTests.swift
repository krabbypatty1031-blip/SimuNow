import Foundation
import Testing
import SimuSimulation
#if os(macOS)
import SimuWorkspace
#endif

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func stagingCopiesWorkerAndP1Helpers() throws {
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-stage-worker-\(UUID().uuidString)", isDirectory: true)
    try WorkerTreeStaging.stageWorker(from: repoRoot(), into: dest)
    #expect(WorkerTreeStaging.isWorkerPresent(in: dest))
    #expect(WorkerTreeStaging.isP1Present(in: dest))
}

/// The L2 pipeline needs the full P1 helper set, not just the L1 IDF writer.
/// Missing helpers would make in-app L2 fail after staging, so assert them here.
@Test func stagingCopiesL2PipelineHelpers() throws {
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("simunow-stage-l2-\(UUID().uuidString)", isDirectory: true)
    try WorkerTreeStaging.stageWorker(from: repoRoot(), into: dest)
    for name in WorkerTreeStaging.l2PipelineScripts {
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appendingPathComponent("test/p1/\(name)").path
            ),
            "staged tree is missing \(name)"
        )
    }
}

/// Engines are never staged into the container: macOS quarantines executables
/// an app writes into its own container (agent = the app, "created without
/// user consent") and the sandboxed app can neither exec nor remove the mark
/// (2026-10-03 hand test: kernel Quarantine deny + EPERM on removexattr with
/// no seatbelt deny log). The staged tree stays Python-only data files; a
/// legacy staged engine tree from an older build must be dropped so the
/// container stops carrying files the sandbox would refuse to run.
@Test func stageWorkerDropsLegacyStagedEngines() throws {
    let fm = FileManager.default
    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-drop-engines-\(UUID().uuidString)", isDirectory: true)
    // Simulate an older build that staged engines beside the worker tree.
    let legacy = runtime.appendingPathComponent("test/engines/EnergyPlus", isDirectory: true)
    try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("legacy staged engine".utf8).write(to: legacy.appendingPathComponent("energyplus-25.2.0"))

    try WorkerTreeStaging.stageWorker(from: repoRoot(), into: runtime)
    #expect(!fm.fileExists(atPath: runtime.appendingPathComponent("test/engines").path))
    // The worker tree itself still lands, so the staged tree stays usable.
    #expect(WorkerTreeStaging.isWorkerPresent(in: runtime))
    #expect(WorkerTreeStaging.isP1Present(in: runtime))
}

#if os(macOS)
@Test func pythonResolverReturnsAStartableInterpreterOrHonestNil() {
    // Default resolution must only return an interpreter that actually
    // started (`canStartInterpreter`), including CLT/Xcode real binaries now
    // that the /usr/bin stub routes through xcrun, which App Sandbox refuses.
    if let url = LocalProcessClient.resolvePythonExecutable() {
        #expect(LocalEngineProbe.hasExecuteBit(at: url.path))
        #expect(url.lastPathComponent.contains("python"))
    }
}

@Test func pythonResolverReturnsNilWhenNoCandidateStarts() {
    // Regression anchor (2026-10-03 hand test): when no candidate can start,
    // the resolver must answer nil instead of falling back to the /usr/bin
    // xcrun stub, which fails inside the App Sandbox with no evidence and
    // turns every submit into a doomed failure.
    let url = LocalProcessClient.resolvePythonExecutable(candidates: ["/nonexistent/python3"])
    #expect(url == nil)
}

@Test func workerEnvironmentPutsDockerOnMinimalSandboxPath() {
    // App Sandbox children inherit `/usr/bin:/bin:/usr/sbin:/sbin`. Docker
    // Desktop installs `docker` at `/usr/local/bin`; without the prefix the
    // L2 wrapper fails as `docker: command not found`.
    let env = LocalProcessClient.workerEnvironment(
        repositoryRoot: URL(fileURLWithPath: "/tmp/simunow-repo"),
        base: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
        extra: ["SIMUNOW_ENGINES_ROOT": "/tmp/engines"]
    )
    #expect(env["PATH"]?.hasPrefix("/usr/local/bin:/opt/homebrew/bin:") == true)
    #expect(env["PYTHONPATH"] == "/tmp/simunow-repo/Backend/src")
    #expect(env["SIMUNOW_ENGINES_ROOT"] == "/tmp/engines")
}

@Test func macReleaseEntitlementsKeepSandbox() throws {
    // Release keeps the file sandbox. temporary-exception.sbpl is not used:
    // on this OS it crashes libsecinit at launch (2026-10-03 hand test).
    let url = repoRoot().appendingPathComponent("Apps/SimuNowMac/SimuNowMac.entitlements")
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url),
        format: nil
    ) as? [String: Any]
    #expect(plist?["com.apple.security.app-sandbox"] as? Bool == true)
    #expect(plist?["com.apple.security.temporary-exception.sbpl"] == nil)
}

@Test func macDebugEntitlementsSkipSandboxForEngineExec() throws {
    // Debug hand-test only: App Sandbox denies process-exec of
    // user-selected EnergyPlus, and the sbpl exception aborts launch.
    let url = repoRoot().appendingPathComponent("Apps/SimuNowMac/SimuNowMacDebug.entitlements")
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url),
        format: nil
    ) as? [String: Any]
    #expect(plist?["com.apple.security.app-sandbox"] == nil)
}

@MainActor
@Test func enginesOnlyWithStagedRepoEnablesSubmit() throws {
    let fm = FileManager.default
    let source = fm.temporaryDirectory.appendingPathComponent("simunow-tiny-engines-\(UUID().uuidString)", isDirectory: true)
    let energyPlus = source.appendingPathComponent("EnergyPlus", isDirectory: true)
    let weather = source.appendingPathComponent("weather", isDirectory: true)
    try fm.createDirectory(at: energyPlus, withIntermediateDirectories: true)
    try fm.createDirectory(at: weather, withIntermediateDirectories: true)
    let binary = energyPlus.appendingPathComponent("energyplus")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    try Data("epw".utf8).write(to: weather.appendingPathComponent("x.epw"))

    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-runtime-\(UUID().uuidString)", isDirectory: true)
    let store = WorkspaceStore()
    store.loadOfficeTemplate()
    store.pendingRepositoryRoot = repoRoot()
    store.applyEnginesOnly(source, runtimeRoot: runtime)
    #expect(store.l1Client.isConfigured)
    #expect(store.canSubmitL1)
    #expect(WorkerTreeStaging.isWorkerPresent(in: runtime))
}
#endif
