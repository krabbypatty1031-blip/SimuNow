import Testing
import Foundation
@testable import SimuCore
@testable import SimuWorkspace

/// Viewport tap placement (2026-10-04): one tap places one item; overlapping
/// or out-of-wall patches are refused before entering the draft, so the
/// draft never gains an overlap from placement. Office template anchors:
/// room 6×6×2.8, one window on xMax s 2.25–3.75 z 0.9–2.2, supply xMin
/// 2.75–3.25 z 2.48–2.66, return xMin 2.7–3.3 z 1.85–2.05, 8 seats, no furniture.
@MainActor
private func makeOfficeStore() -> WorkspaceStore {
    let store = WorkspaceStore()
    store.loadOfficeTemplate()
    return store
}

@Test @MainActor func placeWindowOnEmptyWallAddsWindowWithTemplateFlux() async {
    let store = await makeOfficeStore()
    let before = store.project?.geometry?.openings.count ?? 0
    // yMin wall is empty in the office template.
    let reason = store.placeFromViewport(.window, on: .wall(.yMin, sM: 3.0, zM: 1.55))
    #expect(reason == nil)
    #expect(store.viewportPlacementMessage == nil)
    let openings = store.project?.geometry?.openings ?? []
    #expect(openings.count == before + 1)
    // The default patch: 1.5 × 1.3 centred on the tap.
    let placed = openings.first { $0.wall == .yMin }
    #expect(placed?.s0.value ?? 0 == 2.25)
    #expect(placed?.s1.value ?? 0 == 3.75)
    #expect(placed?.z0.value ?? 0 == 0.9)
    #expect(placed?.z1.value ?? 0 == 2.2)
    // Same template-level 80 W/m² the inspector add-button writes, so both
    // entry points reach both engines (L1 area, L2 declared flux).
    #expect(placed?.heatFluxWm2?.value == 80)
}

@Test @MainActor func placeWindowOnExistingWindowIsRefused() async {
    let store = await makeOfficeStore()
    let before = store.project?.geometry?.openings.count ?? 0
    // Taps the existing xMax window (s 2.25–3.75, z 0.9–2.2).
    let reason = store.placeFromViewport(.window, on: .wall(.xMax, sM: 3.0, zM: 1.55))
    #expect(reason != nil)
    #expect(store.viewportPlacementMessage == reason)
    #expect(reason?.contains("overlap") == true)
    // Refused tap leaves the draft untouched.
    #expect(store.project?.geometry?.openings.count == before)
}

@Test @MainActor func placeDoorStandsOnFloor() async {
    let store = await makeOfficeStore()
    let reason = store.placeFromViewport(.door, on: .wall(.yMax, sM: 3.0, zM: 1.9))
    #expect(reason == nil)
    let door = store.project?.geometry?.openings.first { $0.kind == .door && $0.wall == .yMax }
    #expect(door?.z0.value == 0)
    #expect(abs((door?.z1.value ?? 0) - 2.1) < 1e-9)
}

@Test @MainActor func placeSupplyMovesTerminalAndKeepsFlowConsistent() async {
    let store = await makeOfficeStore()
    // Move supply to the empty yMax wall.
    let reason = store.placeFromViewport(.supplyTerminal, on: .wall(.yMax, sM: 2.0, zM: 2.57))
    #expect(reason == nil)
    let supply = store.project?.hvac?.supply
    #expect(supply?.wall == .yMax)
    #expect(abs((supply?.s0.value ?? 0) - 1.75) < 1e-9)
    #expect(abs((supply?.s1.value ?? 0) - 2.25) < 1e-9)
    // The terminal area is unchanged (same device size), so the
    // speed×area = flow consistency check still passes with the stored values.
    #expect(store.project?.hvacIssues().isEmpty == true)
}

@Test @MainActor func placeSupplyOverlappingWindowIsRefused() async {
    let store = await makeOfficeStore()
    let supplyBefore = store.project?.hvac?.supply
    // The xMax window occupies s 2.25–3.75, z 0.9–2.2; a supply tap at
    // (s 3, z 1.55) lands inside it.
    let reason = store.placeFromViewport(.supplyTerminal, on: .wall(.xMax, sM: 3.0, zM: 1.55))
    #expect(reason != nil)
    #expect(reason?.contains("window") == true)
    #expect(store.project?.hvac?.supply == supplyBefore)
}

@Test @MainActor func placeReturnOverlappingSupplyIsRefused() async {
    let store = await makeOfficeStore()
    let returnBefore = store.project?.hvac?.returnTerminal
    // Supply sits at xMin s 2.75–3.25, z 2.48–2.66; tapping return there
    // overlaps it (return patch s 2.7–3.3, z 2.47–2.67).
    let reason = store.placeFromViewport(.returnTerminal, on: .wall(.xMin, sM: 3.0, zM: 2.57))
    #expect(reason != nil)
    #expect(reason?.contains("Supply outlet") == true)
    #expect(store.project?.hvac?.returnTerminal == returnBefore)
}

@Test @MainActor func placeSeatOnFloorAddsSeatAndHeadcount() async {
    let store = await makeOfficeStore()
    let seatsBefore = store.project?.occupancy?.seats.count ?? 0
    let peopleBefore = store.project?.occupancy?.occupantCount.value ?? 0
    let reason = store.placeFromViewport(.seat, on: .floor(xM: 3.0, yM: 3.0))
    #expect(reason == nil)
    // A new seat is a new person: headcount follows seats.
    #expect(store.project?.occupancy?.seats.count == seatsBefore + 1)
    #expect(store.project?.occupancy?.occupantCount.value == peopleBefore + 1)
    // The seat samples at the 1.1 m sample height at the tapped floor spot.
    let seat = store.project?.occupancy?.seats.last
    #expect(abs((seat?.position.x ?? 0) - 3.0) < 1e-9)
    #expect(abs((seat?.position.y ?? 0) - 3.0) < 1e-9)
    #expect(seat?.position.z == 1.1)
}

@Test @MainActor func placeSeatOnWallIsRefused() async {
    let store = await makeOfficeStore()
    let seatsBefore = store.project?.occupancy?.seats.count ?? 0
    let reason = store.placeFromViewport(.seat, on: .wall(.xMin, sM: 3.0, zM: 1.5))
    #expect(reason != nil)
    #expect(reason?.contains("floor") == true)
    #expect(store.project?.occupancy?.seats.count == seatsBefore)
}

@Test @MainActor func placeWindowOnWallWithoutGeometryRefuses() async {
    let store = await makeOfficeStore()
    store.project = ProjectDraft(name: "空")
    let reason = store.placeFromViewport(.window, on: .wall(.yMin, sM: 3.0, zM: 1.55))
    #expect(reason != nil)
}

/// Same-wall rectangle overlap: both ranges must intersect; touching edges
/// do not count, so patches can sit side by side.
@Test func conflictingWallPatchEdgeAndWallSemantics() {
    var draft = ProjectDraft(name: "重叠测试")
    _ = draft.applyRoomSize(x: 6, y: 4, z: 2.8, source: .user)
    _ = draft.applyOpening(
        id: "W1", kind: .window, wall: .xMax,
        s0: 1.0, s1: 2.5, z0: 0.9, z1: 2.2, source: .user
    )
    // Side-by-side (s1 == otherS0): not a conflict.
    #expect(
        draft.conflictingWallPatch(wall: .xMax, s0: 2.5, s1: 3.5, z0: 0.0, z1: 2.8) == nil
    )
    // Overlapping s-range: conflict.
    let hit = draft.conflictingWallPatch(wall: .xMax, s0: 2.4, s1: 3.5, z0: 0.0, z1: 2.8)
    #expect(hit == .opening(id: "W1", kind: .window))
    // Same s-range but disjoint z-range: not a conflict.
    #expect(
        draft.conflictingWallPatch(wall: .xMax, s0: 1.0, s1: 2.5, z0: 2.2, z1: 2.7) == nil
    )
    // Another wall never conflicts.
    #expect(
        draft.conflictingWallPatch(wall: .yMin, s0: 1.0, s1: 2.5, z0: 0.9, z1: 2.2) == nil
    )
    // Excluding the same opening lets an edit pass its own position.
    #expect(
        draft.conflictingWallPatch(
            wall: .xMax, s0: 1.0, s1: 2.5, z0: 0.9, z1: 2.2,
            excluding: .opening(id: "W1", kind: .window)
        ) == nil
    )
}
