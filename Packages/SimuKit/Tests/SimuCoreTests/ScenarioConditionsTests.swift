import Foundation
import Testing
import SimuCore
import SimuWorkspace

private func conditionFixture() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try ProjectCodec(registry: .builtIn).decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
}

@Test func unchangedConditionsRetainSourcesAndValues() throws {
    let project = try conditionFixture()
    let draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    #expect(try draft.applying(to: project) == project)
}

@Test func conditionEditsAffectOnlySelectedScenarioAndKeepWeather() throws {
    var project = try conditionFixture()
    var second = project.scenarios[0]; second.id = UUID(); second.name = "另一个方案"
    project.scenarios.append(second)
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: second.id)
    draft.outdoorTemperature.enterValue("34")
    draft.indoorHumidity.enterValue("0.55")
    draft.timeZone = "Asia/Shanghai"
    let edited = try draft.applying(to: project)
    #expect(edited.scenarios[0] == project.scenarios[0])
    #expect(edited.scenarios[1].inputs.environment.weather == second.inputs.environment.weather)
    #expect(edited.scenarios[1].inputs.environment.outdoorTemperature.value == 34)
    #expect(edited.scenarios[1].inputs.environment.indoorHumidity.value == 0.55)
}

@Test func boundarySwitchRemovesContradictoryAlternative() throws {
    let project = try conditionFixture()
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    draft.surfaces[0].mode = .heatFlux
    draft.surfaces[0].heatFlux = .init(HeatFlux.known(value: -5, source: .init(kind: .user)))
    let edited = try draft.applying(to: project)
    let boundary = edited.scenarios[0].inputs.envelope.surfaces[0].boundary
    #expect(boundary.mode == .heatFlux && boundary.temperature == nil && boundary.heatFlux?.value == -5)
    #expect(try ProjectValidator().validate(edited, registry: .builtIn).passes(.projectIntegrity))
}

@Test func conditionDraftRejectsIntermediateNumbersAndOutOfRangeHumidity() throws {
    let project = try conditionFixture()
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    draft.outdoorTemperature.enterValue("-")
    #expect(throws: (any Error).self) { try draft.applying(to: project) }
    draft.outdoorTemperature.enterValue("32")
    draft.indoorHumidity.enterValue("55")
    #expect(throws: (any Error).self) { try draft.applying(to: project) }
    #expect(project.scenarios[0].inputs.environment.indoorHumidity.value != 55)
}

@Test func missingConditionsStayAbsentUntilExplicitlyEnabled() throws {
    var project = try conditionFixture()
    project.scenarios[0].inputs.envelope.surfaces.removeAll()
    project.scenarios[0].inputs.ventilation.removeAll()
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    #expect(draft.surfaces.allSatisfy { !$0.isEnabled })
    #expect(try draft.applying(to: project).scenarios[0].inputs.envelope.surfaces.isEmpty)
    draft.surfaces[0].isEnabled = true
    let edited = try draft.applying(to: project)
    #expect(edited.scenarios[0].inputs.envelope.surfaces.count == 1)
    #expect(edited.scenarios[0].inputs.envelope.surfaces[0].uValue.value == nil)
    #expect(edited.scenarios[0].inputs.envelope.surfaces[0].boundary.mode == .fromL1)
}

@Test func unrelatedConditionsEditPreservesAllDuplicateRecordsAndTheirSources() throws {
    var project = try conditionFixture()
    var surface = project.scenarios[0].inputs.envelope.surfaces[0]
    surface.uValue = .known(value: 2.8, source: .init(kind: .measured, reference: "duplicate measurement", note: " Preserve whitespace "))
    project.scenarios[0].inputs.envelope.surfaces.append(surface)
    var window = project.scenarios[0].inputs.envelope.windows[0]
    window.shgc = .known(value: 0.35, source: .init(kind: .manufacturer, reference: "second window specification"))
    project.scenarios[0].inputs.envelope.windows.append(window)
    var ventilation = project.scenarios[0].inputs.ventilation[0]
    ventilation.outdoorAir = .unknown(reason: "second configuration")
    ventilation.openings.append(ventilation.openings[0])
    project.scenarios[0].inputs.ventilation.append(ventilation)
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    #expect(try draft.applying(to: project) == project)
    draft.indoorHumidity.enterValue("0.6")
    let changed = try draft.applying(to: project)
    #expect(changed.scenarios[0].inputs.envelope == project.scenarios[0].inputs.envelope)
    #expect(changed.scenarios[0].inputs.ventilation == project.scenarios[0].inputs.ventilation)
    #expect(changed.scenarios[0].inputs.environment.indoorHumidity.value == 0.6)
    #expect(draft.repairItems.contains { $0.location == .surface(6) })
    #expect(draft.repairItems.contains { $0.location == .window(1) })
    #expect(draft.repairItems.contains { $0.location == .ventilation(1) })
    #expect(draft.repairItems.contains { $0.location == .opening(1, ventilation.openings.count - 1) })
}

@Test func duplicateSelectionEditsOnlyChosenRecordAndExplicitDeleteKeepsOtherRecords() throws {
    var project = try conditionFixture()
    let duplicateIndex = project.scenarios[0].inputs.envelope.surfaces.count
    var duplicate = project.scenarios[0].inputs.envelope.surfaces[0]
    duplicate.uValue = .known(value: 3.5, source: .init(kind: .user, note: "second alternative"))
    project.scenarios[0].inputs.envelope.surfaces.append(duplicate)
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    try draft.selectRepairRecord(.surface(duplicateIndex))
    #expect(draft.surfaces[0].recordIndex == duplicateIndex)
    draft.surfaces[0].uValue.enterValue("4")
    let edited = try draft.applying(to: project)
    #expect(edited.scenarios[0].inputs.envelope.surfaces[0] == project.scenarios[0].inputs.envelope.surfaces[0])
    #expect(edited.scenarios[0].inputs.envelope.surfaces[duplicateIndex].uValue.value == 4)
    #expect(draft.selectionWouldDiscardEdits(.surface(0)))
    try draft.deleteRepairRecord(.surface(0))
    let repaired = try draft.applying(to: project)
    #expect(repaired.scenarios[0].inputs.envelope.surfaces.count == duplicateIndex)
    #expect(repaired.scenarios[0].inputs.envelope.surfaces.last?.uValue.value == 4)
    draft.restoreRepairRecord(.surface(0))
    #expect(try draft.applying(to: project).scenarios[0].inputs.envelope.surfaces.count == duplicateIndex + 1)
}

@Test func missingAndContradictoryBoundaryFieldsRemainUntilExplicitRepair() throws {
    var project = try conditionFixture()
    project.scenarios[0].inputs.envelope.surfaces[0].boundary.heatFlux = .known(value: -7, source: .init(kind: .user, note: "imported alternative"))
    project.scenarios[0].inputs.envelope.surfaces[1].boundary = .init(mode: .temperature)
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    draft.surfaces[0].uValue.enterValue("2.2")
    draft.indoorHumidity.enterValue("0.6")
    let preserved = try draft.applying(to: project)
    #expect(preserved.scenarios[0].inputs.envelope.surfaces[0].boundary == project.scenarios[0].inputs.envelope.surfaces[0].boundary)
    #expect(preserved.scenarios[0].inputs.envelope.surfaces[1].boundary.temperature == nil)
    #expect(draft.repairItems.contains { $0.location == .surface(0) && $0.canNormalizeBoundary })
    try draft.normalizeBoundary(.surface(0))
    try draft.normalizeBoundary(.surface(1))
    let normalized = try draft.applying(to: project)
    #expect(normalized.scenarios[0].inputs.envelope.surfaces[0].boundary.heatFlux == nil)
    #expect(normalized.scenarios[0].inputs.envelope.surfaces[1].boundary.temperature != nil)
    #expect(normalized.scenarios[0].inputs.envelope.surfaces[1].boundary.temperature?.value == nil)
    #expect(!(try ProjectValidator().validate(normalized, registry: .builtIn)).issues.contains { $0.code == "boundary_exclusive" })
}

@Test func orphanConfigurationsAreVisiblePreservedAndExplicitlyRemovable() throws {
    var project = try conditionFixture()
    var surface = project.scenarios[0].inputs.envelope.surfaces[0]; surface.surfaceID = UUID()
    var window = project.scenarios[0].inputs.envelope.windows[0]; window.openingID = UUID()
    var ventilation = project.scenarios[0].inputs.ventilation[0]; ventilation.roomID = UUID()
    let orphanOpening = OpeningState(openingID: UUID(), openFraction: .unknown(reason: "orphan state"))
    project.scenarios[0].inputs.envelope.surfaces.append(surface)
    project.scenarios[0].inputs.envelope.windows.append(window)
    project.scenarios[0].inputs.ventilation.append(ventilation)
    project.scenarios[0].inputs.ventilation[0].openings.append(orphanOpening)
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    #expect(try draft.applying(to: project) == project)
    let orphanSurfaceIndex = project.scenarios[0].inputs.envelope.surfaces.count - 1
    let orphanWindowIndex = project.scenarios[0].inputs.envelope.windows.count - 1
    let orphanOpeningIndex = project.scenarios[0].inputs.ventilation[0].openings.count - 1
    #expect(draft.repairItems.contains { $0.location == .surface(orphanSurfaceIndex) && !$0.canSelect })
    try draft.deleteRepairRecord(.surface(orphanSurfaceIndex))
    try draft.deleteRepairRecord(.window(orphanWindowIndex))
    try draft.deleteRepairRecord(.opening(0, orphanOpeningIndex))
    try draft.deleteRepairRecord(.ventilation(1))
    let repaired = try draft.applying(to: project)
    #expect(repaired.scenarios[0].inputs.envelope.surfaces.count == orphanSurfaceIndex)
    #expect(repaired.scenarios[0].inputs.envelope.windows.count == orphanWindowIndex)
    #expect(repaired.scenarios[0].inputs.ventilation.count == 1)
    #expect(repaired.scenarios[0].inputs.ventilation[0].openings.count == orphanOpeningIndex)
    #expect(try ProjectValidator().validate(repaired, registry: .builtIn).passes(.projectIntegrity))
}

@Test func duplicateOpeningStateSelectionDeletionAndRestorationRetainIdentityAndValues() throws {
    var project = try conditionFixture()
    var second = project.scenarios[0].inputs.ventilation[0].openings[0]
    second.openFraction = .known(value: 0.4, source: .init(kind: .user, note: "second state"))
    let duplicateIndex = project.scenarios[0].inputs.ventilation[0].openings.count
    project.scenarios[0].inputs.ventilation[0].openings.append(second)
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    #expect(try draft.applying(to: project) == project)
    try draft.selectRepairRecord(.opening(0, duplicateIndex))
    draft.ventilation[0].openings[0].openFraction.enterValue("0.7")
    let edited = try draft.applying(to: project)
    #expect(edited.scenarios[0].inputs.ventilation[0].openings[0] == project.scenarios[0].inputs.ventilation[0].openings[0])
    #expect(edited.scenarios[0].inputs.ventilation[0].openings[duplicateIndex].openFraction.value == 0.7)
    try draft.deleteRepairRecord(.opening(0, duplicateIndex))
    #expect(try draft.applying(to: project).scenarios[0].inputs.ventilation[0].openings == project.scenarios[0].inputs.ventilation[0].openings.dropLast())
    draft.restoreRepairRecord(.opening(0, duplicateIndex))
    #expect(try draft.applying(to: project).scenarios[0].inputs.ventilation[0].openings == project.scenarios[0].inputs.ventilation[0].openings)
}

@Test func incompleteOpeningsAndInvalidScalarRecordsAreNotSilentlyCompletedOrRejected() throws {
    var project = try conditionFixture()
    project.scenarios[0].inputs.ventilation[0].openings.removeLast()
    project.scenarios[0].inputs.envelope.surfaces[0].uValue = .known(value: -1, source: .init(kind: .user, note: "invalid imported value"))
    project.scenarios[0].evaluation.cost.tariffs = [.init(startMinute: 0, endMinute: -1,
        rate: .known(value: 0.5, source: .init(kind: .user, note: "invalid imported interval")))]
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    draft.indoorHumidity.enterValue("0.65")
    let preserved = try draft.applying(to: project)
    #expect(preserved.scenarios[0].inputs.ventilation == project.scenarios[0].inputs.ventilation)
    #expect(preserved.scenarios[0].inputs.envelope == project.scenarios[0].inputs.envelope)
    #expect(preserved.scenarios[0].evaluation.cost == project.scenarios[0].evaluation.cost)
}

@Test func duplicateQuoteRecordsHaveDistinctUIIdentitiesAndCanBeRemovedIndividually() throws {
    var project = try conditionFixture()
    let quote = Quote(id: UUID(), amount: .known(value: 800, source: .init(kind: .user)))
    project.scenarios[0].evaluation.cost.quotes = [quote, quote]
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    #expect(draft.quotes[0].id != draft.quotes[1].id)
    #expect(draft.quotes[0].quoteID == draft.quotes[1].quoteID)
    #expect(try draft.applying(to: project) == project)
    draft.quotes.remove(at: 1)
    #expect(try draft.applying(to: project).scenarios[0].evaluation.cost.quotes == [quote])
}

@Test func staleGeometryAndConditionsCannotBeReintroducedByOldDraft() throws {
    let project = try conditionFixture()
    let draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    var changed = project
    changed.geometry.rooms[0].openings.removeLast()
    #expect(throws: (any Error).self) { try draft.applying(to: changed) }
    changed = project
    changed.scenarios[0].inputs.envelope.surfaces.removeLast()
    #expect(throws: (any Error).self) { try draft.applying(to: changed) }
}

@Test func restoringDeletedOriginalRecordDoesNotOverwriteNewFieldDrafts() throws {
    var project = try conditionFixture()
    project.scenarios[0].inputs.envelope.surfaces[0].boundary.heatFlux = .unknown(reason: "imported conflicting alternative")
    var draft = try ScenarioConditionsDraft(project: project, scenarioID: project.scenarios[0].id)
    try draft.deleteRepairRecord(.surface(0))
    draft.surfaces[0].isEnabled = true
    draft.surfaces[0].uValue.isKnown = true
    draft.surfaces[0].uValue.enterValue("2.5")
    draft.restoreRepairRecord(.surface(0))
    #expect(draft.surfaces[0].recordIndex == nil)
    #expect(draft.surfaces[0].uValue.valueText == "2.5")
    let retained = try draft.applying(to: project)
    #expect(retained.scenarios[0].inputs.envelope.surfaces[0] == project.scenarios[0].inputs.envelope.surfaces[0])
    #expect(retained.scenarios[0].inputs.envelope.surfaces.last?.uValue.value == 2.5)
}
