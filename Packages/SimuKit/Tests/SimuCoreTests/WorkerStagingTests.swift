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
    #expect(FileManager.default.isExecutableFile(atPath: LocalEngineProbe.energyPlusURL(in: staged).path))
    #expect(!staged.path.lowercased().contains("/desktop/"))
}

#if os(macOS)
@Test func pythonResolverReturnsAnExecutableWithoutLoginShell() {
    let url = LocalProcessClient.resolvePythonExecutable()
    #expect(FileManager.default.isExecutableFile(atPath: url.path))
    #expect(url.lastPathComponent.contains("python"))
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
