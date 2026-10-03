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

#if canImport(Darwin)
/// Regression anchor (2026-10-03 hand test): macOS quarantines executables a
/// sandboxed app copies into its own container (agent = the app, "created
/// without user consent"), and the sandbox then denies exec and dylib loads
/// of the quarantined unnotarized engine with EPERM (kernel Quarantine deny
/// plus process-exec* deny). Staging must strip the mark from every staged
/// regular file - including read-only dylibs - on every stage call, not only
/// on the copy that created the tree.
@Test func stagingStripsQuarantineFromStagedEngineFiles() throws {
    let fm = FileManager.default
    let source = fm.temporaryDirectory.appendingPathComponent("simunow-q-engines-\(UUID().uuidString)", isDirectory: true)
    let energyPlus = source.appendingPathComponent("EnergyPlus", isDirectory: true)
    try fm.createDirectory(at: energyPlus, withIntermediateDirectories: true)
    try fm.createDirectory(at: source.appendingPathComponent("weather", isDirectory: true), withIntermediateDirectories: true)
    let binary = energyPlus.appendingPathComponent("energyplus")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    // A read-only dylib covers the 444 chmod path a real engine tree has.
    let dylib = energyPlus.appendingPathComponent("libintl.8.dylib")
    try Data("dylib".utf8).write(to: dylib)
    try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dylib.path)
    let wrapper = source.appendingPathComponent("openfoam.sh")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wrapper)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    try Data("epw".utf8).write(to: source.appendingPathComponent("weather/x.epw"))

    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-q-stage-\(UUID().uuidString)", isDirectory: true)
    try WorkerTreeStaging.stageEngines(from: source, into: runtime)
    let staged = WorkerTreeStaging.enginesURL(in: runtime)
    // Quarantine what landed, then re-stage: the EnergyPlus copy is skipped
    // (binary present with x bits), so the strip must also cover files the
    // walk finds already staged, plus the always re-copied wrapper.
    let marks = [
        LocalEngineProbe.energyPlusURL(in: staged),
        staged.appendingPathComponent("EnergyPlus/libintl.8.dylib"),
        staged.appendingPathComponent("openfoam.sh"),
    ]
    for url in marks {
        try setQuarantineFlag(atPath: url.path)
        #expect(hasQuarantineFlag(atPath: url.path))
    }
    try WorkerTreeStaging.stageEngines(from: source, into: runtime)
    for url in marks {
        #expect(!hasQuarantineFlag(atPath: url.path))
    }
    // The 444 dylib keeps its read-only mode after the strip borrows the write bit.
    #expect(try fm.attributesOfItem(atPath: marks[1].path)[.posixPermissions] as? Int == 0o444)
}

private func setQuarantineFlag(atPath path: String) throws {
    // setxattr needs the owner-write bit, same as removexattr. The system
    // quarantines while writing the file; this test writes the mark while
    // the file is writable, then restores the read-only mode so the strip
    // path faces the same 444-plus-quarantine shape the real tree had.
    let fm = FileManager.default
    let original = (try fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? 0o644
    if original & 0o200 == 0 {
        try fm.setAttributes([.posixPermissions: original | 0o200], ofItemAtPath: path)
    }
    defer {
        if original & 0o200 == 0 {
            try? fm.setAttributes([.posixPermissions: original], ofItemAtPath: path)
        }
    }
    let value = "0081;6ac09f5b;TestAgent;"
    let rc = value.withCString { v in
        path.withCString { p in
            setxattr(p, "com.apple.quarantine", v, value.utf8.count, 0, 0)
        }
    }
    #expect(rc == 0, "test could not quarantine \(path)")
}

private func hasQuarantineFlag(atPath path: String) -> Bool {
    getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
}
#endif

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
