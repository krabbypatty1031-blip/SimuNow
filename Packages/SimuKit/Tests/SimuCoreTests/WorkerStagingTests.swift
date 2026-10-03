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

/// run_room.py resolves the OpenFOAM wrapper as <repo>/test/engines/openfoam.sh,
/// so staged engines must land at runtime/test/engines, not runtime/engines.
@Test func stagedEnginesLandBesideP1Helpers() throws {
    let fm = FileManager.default
    let source = fm.temporaryDirectory.appendingPathComponent("simunow-tiny-engines-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: source.appendingPathComponent("EnergyPlus", isDirectory: true), withIntermediateDirectories: true)
    try fm.createDirectory(at: source.appendingPathComponent("weather", isDirectory: true), withIntermediateDirectories: true)
    let binary = source.appendingPathComponent("EnergyPlus/energyplus")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    try Data("epw".utf8).write(to: source.appendingPathComponent("weather/x.epw"))

    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-stage-engines-\(UUID().uuidString)", isDirectory: true)
    try WorkerTreeStaging.stageEngines(from: source, into: runtime)
    let staged = WorkerTreeStaging.enginesURL(in: runtime)
    #expect(staged.path.hasSuffix("test/engines"))
    #expect(FileManager.default.isExecutableFile(atPath: LocalEngineProbe.energyPlusURL(in: staged).path))
}

@Test func stagingCopiesTinyEngineTreeWithoutDesktopPath() throws {
    let fm = FileManager.default
    let source = fm.temporaryDirectory.appendingPathComponent("simunow-tiny-engines-\(UUID().uuidString)", isDirectory: true)
    let energyPlus = source.appendingPathComponent("EnergyPlus", isDirectory: true)
    let weather = source.appendingPathComponent("weather", isDirectory: true)
    try fm.createDirectory(at: energyPlus, withIntermediateDirectories: true)
    try fm.createDirectory(at: weather, withIntermediateDirectories: true)
    let binary = energyPlus.appendingPathComponent("energyplus")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    try Data("epw".utf8).write(to: weather.appendingPathComponent("CHN_Hong.Kong.SAR.450070_CityUHK.epw"))

    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-stage-engines-\(UUID().uuidString)", isDirectory: true)
    try WorkerTreeStaging.stageEngines(from: source, into: runtime)
    let staged = WorkerTreeStaging.enginesURL(in: runtime)
    // POSIX bits via stat, matching the in-app probe semantics (ADR-011 addendum).
    #expect(LocalEngineProbe.hasExecuteBit(at: LocalEngineProbe.energyPlusURL(in: staged).path))
    #expect(!staged.path.lowercased().contains("/desktop/"))
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
