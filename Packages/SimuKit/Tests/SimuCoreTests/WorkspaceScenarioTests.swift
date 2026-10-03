import Foundation
import Testing
import SimuCore
import SimuWorkspace

/// P2-05c: 方案对比读的是 store 里冻结基准 vs 当前编辑，不是同一份可变 draft。
@MainActor
@Test func workspaceScenarioCompareKeepsFrozenBaselineAfterSizeEdit() throws {
    let store = WorkspaceStore()
    store.selection = .scenarios
    #expect(store.baseline == nil)
    #expect(store.project == nil)

    store.loadOfficeTemplate()
    let baselineLength = try #require(store.baseline?.geometry?.sizeX.value)
    let currentLength = try #require(store.project?.geometry?.sizeX.value)
    #expect(baselineLength == 6)
    #expect(currentLength == 6)
    #expect(store.baselineScenarioID != nil)
    #expect(store.project?.id != store.baseline?.id)

    store.applyRoomSize(x: 7, y: 6, z: 2.8)
    #expect(store.project?.geometry?.sizeX.value == 7)
    #expect(store.baseline?.geometry?.sizeX.value == 6)
    #expect(store.baseline?.geometry?.sizeY.value == 6)
    #expect(store.baseline?.geometry?.sizeZ.value == 2.8)
    #expect(store.selection == .scenarios)
}

@MainActor
@Test func openingPackageIgnoresUnfinishedRunAndKeepsCurrentProject() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("simunow-p3-05c-\(UUID().uuidString)", isDirectory: true)
    let url = folder.appendingPathComponent("Office.simunow", isDirectory: true)
    var draft = try ProjectTemplates.bundled(named: "office").project
    draft.name = "当前方案"
    try ProjectPackage.save(draft, to: url)
    let runDir = url.appendingPathComponent("runs/dead-run", isDirectory: true)
    try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
    try Data(#"{"state":"solving"}"#.utf8).write(to: runDir.appendingPathComponent("status.json"))

    let store = WorkspaceStore()
    store.openPackage(at: url)
    #expect(store.project?.name == "当前方案")
    #expect(store.project?.geometry?.sizeX.value == 6)
    #expect(store.packageError == nil)
}
