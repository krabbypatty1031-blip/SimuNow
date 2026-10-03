import Foundation
import Testing
@testable import SimuCore

@Test func newDraftStaysIdentityUntilSizeApplied() {
    var draft = ProjectDraft(name: "办公室")
    #expect(draft.schemaVersion == 1)
    #expect(draft.geometry == nil)

    let issues = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    #expect(issues.isEmpty)
    #expect(draft.schemaVersion == 1)
    #expect(draft.geometry?.sizeX.value == 6)
    #expect(draft.geometry?.sizeY.value == 6)
    #expect(draft.geometry?.sizeZ.value == 2.8)
    #expect(draft.geometry?.sizeX.unit == "m")
    #expect(draft.geometry?.sizeX.source == .user)
    #expect(draft.hasCompletePhysicalModel == false)
}

@Test func applyingSizeUpdatesExistingLength() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    let issues = draft.applyRoomSize(x: 7, y: 6, z: 2.8, source: .user)
    #expect(issues.isEmpty)
    #expect(draft.geometry?.sizeX.value == 7)
}

@Test func nonPositiveRoomSizeIsRejected() {
    var draft = ProjectDraft(name: "办公室")
    let issues = draft.applyRoomSize(x: 0, y: 6, z: 2.8, source: .user)
    #expect(issues.contains { $0.path == "geometry.sizeX" })
    #expect(draft.geometry == nil)
}

@Test func openingPastWallReportsIssueAndDoesNotClamp() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    let opening = Opening(
        id: "W1",
        kind: .window,
        wall: .xMax,
        s0: PhysicalQuantity(value: 0, unit: "m", source: .user),
        s1: PhysicalQuantity(value: 9, unit: "m", source: .user),
        z0: PhysicalQuantity(value: 0.9, unit: "m", source: .user),
        z1: PhysicalQuantity(value: 2.2, unit: "m", source: .user)
    )
    let issues = draft.upsertOpening(opening)
    #expect(issues.contains { $0.path == "geometry.openings.W1" })
    #expect(draft.geometry?.openings.first?.s1.value == 9)
    #expect(draft.hasCompletePhysicalModel == false)
}

@Test func northYawRoundTripsWithoutRotatingOpeningSpan() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.upsertOpening(
        Opening(
            id: "W1",
            kind: .window,
            wall: .xMax,
            s0: PhysicalQuantity(value: 2.25, unit: "m", source: .user),
            s1: PhysicalQuantity(value: 3.75, unit: "m", source: .user),
            z0: PhysicalQuantity(value: 0.9, unit: "m", source: .user),
            z1: PhysicalQuantity(value: 2.2, unit: "m", source: .user)
        )
    )
    let issues = draft.applyNorthYawDegrees(90, source: .user)
    #expect(issues.isEmpty)
    let restored = try JSONDecoder().decode(ProjectDraft.self, from: JSONEncoder().encode(draft))
    #expect(restored.geometry?.northYawDegrees.value == 90)
    #expect(restored.geometry?.northYawDegrees.unit == "deg")
    #expect(restored.geometry?.openings.first?.s0.value == 2.25)
}

@Test func listedAssumptionsShowNotesAndUnknownProvenance() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    draft.geometry?.assumptions = ["omitted: furniture_boxes"]
    let listed = draft.listedAssumptions()
    #expect(listed.contains { $0.note == "omitted: furniture_boxes" })
    let yaw = listed.first { $0.path == "geometry.northYawDegrees" }
    #expect(yaw?.source == .assumed)
    #expect(yaw?.provenanceText == "Working assumption")
    #expect(listed.allSatisfy { $0.provenanceText != "0" })
}

@Test func openingNumericEditWritesWallSpanKindAndSource() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    let issues = draft.applyOpening(
        id: "W1",
        kind: .window,
        wall: .yMin,
        s0: 0.5,
        s1: 2.0,
        z0: 0.9,
        z1: 2.2,
        source: .measured
    )
    #expect(issues.isEmpty)
    let opening = draft.geometry?.openings.first { $0.id == "W1" }
    #expect(opening?.kind == .window)
    #expect(opening?.wall == .yMin)
    #expect(opening?.s0.value == 0.5)
    #expect(opening?.s1.value == 2.0)
    #expect(opening?.z0.value == 0.9)
    #expect(opening?.z1.value == 2.2)
    #expect(opening?.s0.unit == "m")
    #expect(opening?.s0.source == .measured)
    #expect(opening?.s1.source == .measured)
    #expect(opening?.z0.source == .measured)
    #expect(opening?.z1.source == .measured)
}

@Test func deletingOpeningRemovesItWithoutClampingOthers() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.applyOpening(id: "W1", kind: .window, wall: .xMax, s0: 0.5, s1: 2.0, z0: 0.9, z1: 2.2, source: .user)
    _ = draft.applyOpening(id: "D1", kind: .door, wall: .yMin, s0: 0.2, s1: 1.1, z0: 0, z1: 2.1, source: .user)
    draft.removeOpening(id: "W1")
    #expect(draft.geometry?.openings.map(\.id) == ["D1"])
    #expect(draft.geometry?.openings.first?.s1.value == 1.1)
}

@Test func listedAssumptionsShowUncertaintyInSameUnitWhenPresent() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    draft.geometry?.northYawDegrees = PhysicalQuantity(
        value: 0,
        unit: "deg",
        source: .assumed,
        uncertainty: 5
    )
    let yaw = draft.listedAssumptions().first { $0.path == "geometry.northYawDegrees" }
    #expect(yaw?.uncertainty == 5)
    #expect(yaw?.unit == "deg")
    #expect(yaw?.provenanceText.contains("5") == true)
    #expect(yaw?.provenanceText.contains("deg") == true)
    #expect(yaw?.provenanceText.contains("Working assumption") == true)
}

@Test func applyOccupantCountRejectsNonPositiveAndKeepsHeadcount() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    let issues = draft.applyOccupantCount(0, source: .user)
    #expect(issues.contains { $0.path == "occupancy.occupantCount" })
    #expect(draft.occupancy?.occupantCount.value == 8)
    #expect(draft.occupancy?.seats.count == 8)
}

@Test func addingASeatIncrementsOccupantCount() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.occupancy?.occupantCount.value == Double(draft.occupancy?.seats.count ?? -1))
    let issues = draft.applySeat(id: "S9", position: Position3D(x: 3, y: 3, z: 1.1), source: .user)
    #expect(issues.isEmpty)
    #expect(draft.occupancy?.seats.count == 9)
    #expect(draft.occupancy?.occupantCount.value == 9)
}

@Test func movingASeatDoesNotChangeOccupantCount() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    let issues = draft.applySeat(id: "S1", position: Position3D(x: 2, y: 2, z: 1.1), source: .user)
    #expect(issues.isEmpty)
    #expect(draft.occupancy?.seats.count == 8)
    #expect(draft.occupancy?.occupantCount.value == 8)
}

@Test func applyOccupantCountAddsAndRemovesSeatsToMatch() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.applyOccupantCount(3, source: .user).isEmpty)
    #expect(draft.occupancy?.occupantCount.value == 3)
    #expect(draft.occupancy?.seats.count == 3)
    #expect(draft.applyOccupantCount(5, source: .user).isEmpty)
    #expect(draft.occupancy?.occupantCount.value == 5)
    #expect(draft.occupancy?.seats.count == 5)
}

@Test func removingTheLastSeatIsRefused() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.applyOccupantCount(1, source: .user).isEmpty)
    let remaining = try #require(draft.occupancy?.seats.first?.id)
    let issues = draft.removeSeat(id: remaining)
    #expect(issues.contains { $0.path == "occupancy.seats.\(remaining)" })
    #expect(draft.occupancy?.seats.count == 1)
    #expect(draft.occupancy?.occupantCount.value == 1)
}

@Test func mismatchedPeopleAndSeatsAreAFieldIssue() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    draft.occupancy?.occupantCount.value = 3
    #expect(draft.seatIssues().contains { $0.path == "occupancy.occupantCount" })
}

@Test func applyOccupiedHoursWritesPeopleAndHVACWindows() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    let issues = draft.applyOccupiedHours(start: "09:00", end: "17:00", source: .user)
    #expect(issues.isEmpty)
    #expect(draft.occupancy?.schedule?.start == "09:00")
    #expect(draft.occupancy?.schedule?.end == "17:00")
    #expect(draft.hvac?.schedule?.start == "09:00")
    #expect(draft.hvac?.schedule?.end == "17:00")
}

@Test func applyOccupiedHoursRejectsInvertedWindow() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    let issues = draft.applyOccupiedHours(start: "18:00", end: "08:00", source: .user)
    #expect(issues.contains { $0.path == "occupancy.schedule" })
    #expect(draft.occupancy?.schedule?.start == "08:00")
    #expect(draft.occupancy?.schedule?.end == "18:00")
}

@Test func removingHVACClearsTheSplitACWithoutTouchingSeatsOrOpenings() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    #expect(draft.hvac != nil)
    let seatCount = draft.occupancy?.seats.count
    let openingIDs = draft.geometry?.openings.map(\.id)
    draft.removeHVAC()
    #expect(draft.hvac == nil)
    #expect(draft.occupancy?.seats.count == seatCount)
    #expect(draft.geometry?.openings.map(\.id) == openingIDs)
    // The same install path the inspector uses must put a split AC back.
    _ = draft.installDefaultSplitAC()
    #expect(draft.hvac?.kind == .splitAC)
    #expect(draft.hvac?.supply.id == "SUP1")
}

@Test func editingAWindowKeepsItsStoredHeatFlux() throws {
    // ADR-017: the editor has no flux field. Applying a window edit must keep
    // the template's declared 80 W/m2, or the L2 field would silently lose the
    // window heat the user never touched.
    var draft = try ProjectTemplates.bundled(named: "office").project
    let issues = draft.applyOpening(
        id: "W1",
        kind: .window,
        wall: .xMax,
        s0: 2.0,
        s1: 4.0,
        z0: 0.9,
        z1: 2.2,
        source: .user
    )
    #expect(issues.isEmpty)
    let opening = draft.geometry?.openings.first { $0.id == "W1" }
    #expect(opening?.heatFluxWm2?.value == 80)
    #expect(opening?.heatFluxWm2?.unit == "W/m2")
    #expect(opening?.heatFluxWm2?.source == .preset)
    #expect(opening?.s0.value == 2.0)
}

@Test func applyOpeningWritesAnExplicitHeatFlux() throws {
    // The addOpening path passes an explicit flux (template-level 80 W/m2,
    // assumed) so a NEW window reaches both engines: L1 area and L2 watts.
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.applyOpening(
        id: "W1",
        kind: .window,
        wall: .xMax,
        s0: 0.5,
        s1: 2.0,
        z0: 0.9,
        z1: 2.2,
        source: .user,
        heatFluxWm2: PhysicalQuantity(value: 80, unit: "W/m2", source: .assumed)
    )
    #expect(draft.geometry?.openings.first?.heatFluxWm2?.value == 80)
    #expect(draft.geometry?.openings.first?.heatFluxWm2?.source == .assumed)
}
