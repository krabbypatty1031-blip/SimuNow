import Foundation
import Testing
import SimuCore
import SimuSimulation

#if os(macOS)
private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// In-app L2 submission must refuse when no engine is configured.
/// A refusal is evidence; fabricated fields or comfort metrics are not.
@Test func unconfiguredL2ClientRefusesToSubmit() async throws {
    let client = UnconfiguredL2TaskClient()
    #expect(!client.isConfigured)
    let request = SimulationRequest(
        identity: RunIdentity(runID: UUID(), scenarioID: UUID(), inputHash: String(repeating: "0", count: 64)),
        fidelity: .l2,
        snapshotPath: "input.json",
        snapshotHash: String(repeating: "0", count: 64)
    )
    do {
        _ = try await client.submitL2(request, snapshot: Data("{}".utf8))
        Issue.record("unconfigured L2 client must throw")
    } catch {
        #expect(error is SimulationClientError)
    }
}

/// LocalProcessL2Client is configured once the staged worker tree and an
/// OpenFOAM wrapper are both present. Whether Docker itself is reachable is
/// discovered at run time; a failed run stays failed.
@Test func localL2ClientConfiguredWithOpenFOAMWrapper() throws {
    let fm = FileManager.default
    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-l2cfg-\(UUID().uuidString)", isDirectory: true)
    // Minimal staged worker tree: only the files the probe checks.
    try fm.createDirectory(
        at: runtime.appendingPathComponent("Backend/src/simunow_worker", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("# stub worker\n".utf8).write(
        to: runtime.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
    )
    let engines = WorkerTreeStaging.enginesURL(in: runtime)
    try fm.createDirectory(at: engines, withIntermediateDirectories: true)
    let wrapper = engines.appendingPathComponent("openfoam.sh")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wrapper)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

    let client = LocalProcessL2Client(
        repositoryRoot: runtime,
        enginesRoot: engines,
        runRoot: fm.temporaryDirectory.appendingPathComponent("simunow-l2runs-\(UUID().uuidString)")
    )
    #expect(client.isConfigured)
}

/// Without the OpenFOAM wrapper the client must stay unconfigured so the UI
/// can disable the L2 button instead of promising a run it cannot perform.
@Test func localL2ClientUnconfiguredWithoutWrapper() throws {
    let fm = FileManager.default
    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-l2cfg-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(
        at: runtime.appendingPathComponent("Backend/src/simunow_worker", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("# stub worker\n".utf8).write(
        to: runtime.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
    )
    let engines = WorkerTreeStaging.enginesURL(in: runtime)
    try fm.createDirectory(at: engines, withIntermediateDirectories: true)

    let client = LocalProcessL2Client(
        repositoryRoot: runtime,
        enginesRoot: engines,
        runRoot: fm.temporaryDirectory
    )
    #expect(!client.isConfigured)
}

/// The App reads the quality-gated seat-height slice written by run-l2.
/// Quality-failed runs write no slice file; loading then returns nil, not a fake slice.
@Test func localL2ClientLoadsWrittenFieldSlice() async throws {
    let fm = FileManager.default
    let runRoot = fm.temporaryDirectory.appendingPathComponent("simunow-l2slice-\(UUID().uuidString)", isDirectory: true)
    let runID = UUID()
    let runDir = runRoot.appendingPathComponent(runID.uuidString, isDirectory: true)
    try fm.createDirectory(at: runDir, withIntermediateDirectories: true)
    // Copy the pinned fixture: a real 24x24 seat-height slice from a passing run.
    let fixture = repoRoot()
        .appendingPathComponent("Fixtures/task/field-slice-l2.json")
    try fm.copyItem(at: fixture, to: runDir.appendingPathComponent("field-slice.json"))

    let runtime = fm.temporaryDirectory.appendingPathComponent("simunow-l2cfg-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(
        at: runtime.appendingPathComponent("Backend/src/simunow_worker", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("# stub worker\n".utf8).write(
        to: runtime.appendingPathComponent("Backend/src/simunow_worker/__main__.py")
    )
    let engines = WorkerTreeStaging.enginesURL(in: runtime)
    try fm.createDirectory(at: engines, withIntermediateDirectories: true)

    let client = LocalProcessL2Client(repositoryRoot: runtime, enginesRoot: engines, runRoot: runRoot)
    let slice = try await client.loadFieldSlice(runID: runID)
    #expect(slice != nil)
    #expect(slice?.quality == "passed")
    #expect(slice?.shape.nx == 24)
    #expect(slice?.shape.ny == 24)
    #expect(abs(slice!.zM - 1.1) < 1e-9)

    // No run directory -> nil, never a fabricated slice.
    #expect(try await client.loadFieldSlice(runID: UUID()) == nil)
}
#endif
