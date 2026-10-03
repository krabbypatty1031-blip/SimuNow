import Foundation
import Testing
@testable import SimuCore

@Test func furnitureBoxOutsideRoomIsRejected() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    let issues = draft.upsertObstacle(
        ObstacleBox(id: "F1", origin: Position3D(x: 5.5, y: 0, z: 0), size: Position3D(x: 1.0, y: 1.0, z: 1.0))
    )
    #expect(issues.contains { $0.path == "geometry.obstacles.F1" })
}

@Test func seatOutsideFluidDomainIsRejected() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    let issues = draft.upsertSeat(Seat(id: "S1", position: Position3D(x: -0.1, y: 1, z: 1.1), source: .user))
    #expect(issues.contains { $0.path == "occupancy.seats.S1" })
}

@Test func supplyAirflowMismatchIsABlockingIssue() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    var hvac = try #require(draft.hvac)
    hvac.supplyAirflowM3s.value = 9
    let issues = draft.applyHVAC(hvac)
    #expect(issues.contains { $0.path == "hvac.supplyAirflowM3s" })
}

@Test func supplyTerminalNumericEditKeepsIdAndReportsOutOfWall() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    let supplyId = try #require(draft.hvac?.supply.id)
    let issues = draft.applySupplyTerminal(
        wall: .xMax,
        s0: 0.1,
        s1: 9.0,
        z0: 2.48,
        z1: 2.66,
        source: .user
    )
    #expect(issues.contains { $0.path == "hvac.supply" })
    #expect(draft.hvac?.supply.id == supplyId)
    #expect(draft.hvac?.supply.wall == .xMax)
    #expect(draft.hvac?.supply.s1.value == 9.0)
    #expect(draft.hvac?.returnTerminal.id == "RET1")
}

@Test func returnAndOutdoorAirAreEditedSeparately() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    let returnId = try #require(draft.hvac?.returnTerminal.id)
    let returnIssues = draft.applyReturnTerminal(
        wall: .yMax,
        s0: 0.4,
        s1: 1.1,
        z0: 0.2,
        z1: 0.5,
        source: .measured
    )
    let outdoorIssues = draft.applyOutdoorAirM3s(0.05, source: .user)
    #expect(returnIssues.isEmpty)
    #expect(outdoorIssues.isEmpty)
    #expect(draft.hvac?.returnTerminal.id == returnId)
    #expect(draft.hvac?.returnTerminal.wall == .yMax)
    #expect(draft.hvac?.returnTerminal.s0.source == .measured)
    #expect(draft.hvac?.outdoorAirM3s.value == 0.05)
    #expect(draft.hvac?.outdoorAirM3s.unit == "m3/s")
    #expect(draft.hvac?.outdoorAirM3s.source == .user)
}

@Test func recomputingAirflowFromSpeedAndAreaClearsMismatch() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    var hvac = try #require(draft.hvac)
    hvac.supplyAirflowM3s.value = 9
    _ = draft.applyHVAC(hvac)
    let hvacAfterMismatch = try #require(draft.hvac)
    let expected = hvacAfterMismatch.supplySpeedMs.value * hvacAfterMismatch.supply.patchAreaM2
    let issues = draft.recomputeSupplyAirflowFromSpeedAndArea()
    #expect(!issues.contains { $0.path == "hvac.supplyAirflowM3s" })
    #expect(abs((draft.hvac?.supplyAirflowM3s.value ?? -1) - expected) < 1e-9)
}

@Test func applyingSupplySpeedRecomputesAirflowFromPatchArea() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    let area = try #require(draft.hvac?.supply.patchAreaM2)
    let issues = draft.applySupplySpeedMs(2.0, source: .user)
    #expect(issues.isEmpty)
    #expect(draft.hvac?.supplySpeedMs.value == 2.0)
    #expect(abs((draft.hvac?.supplyAirflowM3s.value ?? -1) - 2.0 * area) < 1e-9)
}

@Test func identicalSupplyAndReturnPatchesAreRejected() throws {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.installDefaultSplitAC()
    let supply = try #require(draft.hvac?.supply)
    _ = draft.applyReturnTerminal(
        wall: supply.wall,
        s0: supply.s0.value,
        s1: supply.s1.value,
        z0: supply.z0.value,
        z1: supply.z1.value,
        source: .user
    )
    #expect(draft.hvacIssues().contains { $0.path == "hvac.returnTerminal" })
}

@Test func furnitureAndSeatCanBeRemovedAfterNumericEdit() {
    var draft = ProjectDraft(name: "办公室")
    _ = draft.applyRoomSize(x: 6, y: 6, z: 2.8, source: .user)
    _ = draft.applyObstacle(
        id: "F1",
        origin: Position3D(x: 1, y: 1, z: 0),
        size: Position3D(x: 1.2, y: 0.7, z: 0.75)
    )
    _ = draft.applySeat(id: "S1", position: Position3D(x: 1.5, y: 1.5, z: 1.1), source: .user)
    _ = draft.applySeat(id: "S2", position: Position3D(x: 2.5, y: 2.5, z: 1.1), source: .user)
    draft.removeObstacle(id: "F1")
    _ = draft.removeSeat(id: "S1")
    #expect(draft.geometry?.obstacles.isEmpty == true)
    #expect(draft.occupancy?.seats.map(\.id) == ["S2"])
    #expect(draft.occupancy?.occupantCount.value == 1)
}

@Test func nextPrefixedIDSkipsExistingRatherThanOverwriting() {
    #expect(ProjectDraft.nextPrefixedID(prefix: "F", existing: ["F1", "F2"]) == "F3")
    #expect(ProjectDraft.nextPrefixedID(prefix: "F", existing: ["F2"]) == "F1")
    #expect(ProjectDraft.nextPrefixedID(prefix: "S", existing: []) == "S1")
}

@Test func displayAndComputationCoordinatesRoundTrip() {
    let display = Position3D(x: 1.25, y: 2.5, z: -3)
    let computation = CoordinateMapping.toComputation(display)
    let back = CoordinateMapping.toDisplay(computation)
    #expect(abs(back.x - display.x) < 1e-9)
    #expect(abs(back.y - display.y) < 1e-9)
    #expect(abs(back.z - display.z) < 1e-9)
    #expect(computation.z == display.y)
}
