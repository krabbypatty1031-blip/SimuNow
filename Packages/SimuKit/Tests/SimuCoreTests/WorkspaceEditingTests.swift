import Foundation
import Testing
import SimuCore
import SimuWorkspace

private func workspaceFixture() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json"))
    return try ProjectCodec(registry: .builtIn).decode(data)
}

@Test @MainActor func workspaceTransactionsUndoWholeValuesAndPublishOnce() throws {
    let original = try workspaceFixture()
    let store = WorkspaceStore()
    store.load(original, baselineScenarioID: original.scenarios[0].id)
    var published: [WorkspaceProjectState] = []
    store.onDocumentChange = { published.append($0) }
    var candidate = original
    candidate.scenarios[0].inputs.controls[0].setpoint = .known(value: 27, source: .init(kind: .user, note: "现场调整"))
    try store.replaceProject(candidate, actionName: "调整设定温度")
    #expect(store.canUndo && !store.canRedo)
    #expect(published.count == 1)
    store.undo()
    #expect(store.project == original)
    #expect(published.count == 2)
    store.redo()
    #expect(store.project == candidate)
    #expect(published.count == 3)
    store.undo()
    var divergent = original; divergent.name = "另一个编辑"
    try store.replaceProject(divergent, actionName: "改名")
    #expect(!store.canRedo)
}

@Test @MainActor func rejectedGeometryNeverReachesDocumentBinding() throws {
    let original = try workspaceFixture()
    let store = WorkspaceStore(); store.load(original)
    var publications = 0
    store.onDocumentChange = { _ in publications += 1 }
    var candidate = original
    candidate.scenarios[0].inputs.usage.seats[0].samples[0].position.x = -100
    #expect(throws: (any Error).self) { try store.replaceProject(candidate, actionName: "越界") }
    #expect(store.project == original)
    #expect(!store.canUndo && publications == 0)
}

@Test @MainActor func selectedPreparationIgnoresIncompleteCandidatesAndRemapsPaths() throws {
    var project = try workspaceFixture()
    let completeID = project.scenarios[0].id
    project.scenarios.append(.unfinished(name: "待编辑候选"))
    let store = WorkspaceStore(); store.load(project, baselineScenarioID: completeID)
    #expect(store.integrityReport.passes(.projectIntegrity))
    #expect(!store.integrityReport.passes(.inputPreparation))
    #expect(store.selectedScenarioReport.passes(.inputPreparation))
    store.selectedScenarioID = project.scenarios[1].id
    #expect(!store.selectedScenarioReport.passes(.inputPreparation))
    #expect(store.selectedScenarioReport.issues.contains { $0.path.hasPrefix("/scenarios/1/") })
    #expect(!store.selectedScenarioReport.issues.contains { $0.path.hasPrefix("/scenarios/0/") })
}

@Test @MainActor func baselineDeletionAndUndoAreAtomic() throws {
    var project = try workspaceFixture()
    var copied = project.scenarios[0]; copied.id = UUID(); copied.name = "候选"
    project.scenarios.append(copied)
    let store = WorkspaceStore(); store.load(project, baselineScenarioID: project.scenarios[0].id)
    var candidate = project; candidate.scenarios.removeFirst()
    #expect(throws: (any Error).self) { try store.replaceProject(candidate, actionName: "删除基准") }
    try store.replaceScenarios(candidate, baselineScenarioID: copied.id, actionName: "替换基准")
    #expect(store.project == candidate && store.baselineScenarioID == copied.id)
    store.undo()
    #expect(store.project == project && store.baselineScenarioID == project.scenarios[0].id)
}

@Test @MainActor func repairEditsCannotIntroduceNewIntegrityFailures() throws {
    var broken = try workspaceFixture()
    broken.scenarios[0].inputs.usage.seats[0].samples[0].position.x = -1
    let store = WorkspaceStore(); store.load(broken)
    #expect(!store.integrityReport.passes(.projectIntegrity))
    var renamed = broken; renamed.name = "修复中"
    try store.replaceProject(renamed, actionName: "改名")
    var worse = renamed
    worse.scenarios[0].inputs.controls[0].sensorPosition.x = -2
    #expect(throws: (any Error).self) { try store.replaceProject(worse, actionName: "引入新问题") }
    var repaired = renamed
    repaired.scenarios[0].inputs.usage.seats[0].samples[0].position.x = 1
    try store.replaceProject(repaired, actionName: "修复采样点")
    #expect(store.integrityReport.passes(.projectIntegrity))
}

@Test @MainActor func capturedWorkspaceInputKeepsOriginalValues() throws {
    let project = try workspaceFixture()
    let store = WorkspaceStore(); store.load(project)
    let snapshot = try store.captureSelectedInput()
    var changed = project
    changed.scenarios[0].inputs.controls[0].setpoint = .known(value: 29, source: .init(kind: .user))
    try store.replaceProject(changed, actionName: "温度修改")
    #expect(store.capturedInput == snapshot)
    #expect(snapshot.inputs.controls[0].setpoint.value == 25)
    #expect(store.currentScenario?.inputs.controls[0].setpoint.value == 29)
}

@Test @MainActor func repairCannotTransferAnIssueToAnotherScenarioWithTheSameNestedID() throws {
    var original = try workspaceFixture()
    var copy = original.scenarios[0]; copy.id = UUID(); copy.name = "候选"
    original.scenarios.append(copy)
    original.scenarios[0].inputs.usage.seats[0].samples[0].position.x = -1
    let store = WorkspaceStore(); store.load(original)
    var movedIssue = original
    movedIssue.scenarios[0].inputs.usage.seats[0].samples[0].position.x = 1
    movedIssue.scenarios[1].inputs.usage.seats[0].samples[0].position.x = -1
    #expect(throws: (any Error).self) { try store.replaceProject(movedIssue, actionName: "转移错误") }
    #expect(store.project == original && !store.canUndo)
}

@Test @MainActor func documentPreflightRejectsWithoutPublishingOrChangingHistory() throws {
    let project = try workspaceFixture()
    let store = WorkspaceStore(); store.load(project)
    store.validateDocumentChange = { _ in throw ProjectPackageError.resourceLimit("测试配额") }
    var publications = 0
    store.onDocumentChange = { _ in publications += 1 }
    var next = project; next.name = "不能提交"
    #expect(throws: (any Error).self) { try store.replaceProject(next, actionName: "更名") }
    #expect(store.project == project && !store.canUndo && publications == 0)
}
