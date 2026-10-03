import Testing
import Foundation
@testable import SimuVisualization
import SimuCore

/// Tap-placement geometry: the display→draft unprojection, wall/floor
/// surface resolution, and the default patch shapes. Pure math — no
/// RealityKit entities are needed.
@Test func displayToComputationRoundTripsCenteredDisplay() {
    // centeredDisplay(c) = toDisplay(c) − toDisplay(room centre); the
    // placement unprojection must invert it exactly.
    let sizeXM = 6.0, sizeYM = 4.5, sizeZM = 2.8
    for c in [
        Position3D(x: 0.2, y: 0.1, z: 0.05),
        Position3D(x: 3.0, y: 2.25, z: 1.4),   // room centre
        Position3D(x: 5.9, y: 4.4, z: 2.75),
        Position3D(x: 0.0, y: 4.5, z: 2.8),
    ] {
        let centre = CoordinateMapping.toDisplay(
            Position3D(x: sizeXM / 2, y: sizeYM / 2, z: sizeZM / 2)
        )
        let d = CoordinateMapping.toDisplay(c)
        let back = PlacementGeometry.computationFromDisplay(
            displayX: d.x - centre.x,
            displayY: d.y - centre.y,
            displayZ: d.z - centre.z,
            sizeXM: sizeXM,
            sizeYM: sizeYM,
            sizeZM: sizeZM
        )
        #expect(abs(back.x - c.x) < 1e-9)
        #expect(abs(back.y - c.y) < 1e-9)
        #expect(abs(back.z - c.z) < 1e-9)
    }
}

@Test func wallSurfaceFollowsWallLocalSConvention() {
    // s runs along Y on xMin/xMax walls and along X on yMin/yMax walls;
    // z is height. Computation frame is Z-up metres.
    // A hit resolving to computation (0.5, 0, 1.5) on yMin (s along X):
    // display = (0.5−3, 1.5−1.4, 0+2) = (−2.5, 0.1, 2).
    let s = PlacementGeometry.wallSurface(
        wall: .yMin,
        displayX: -2.5, displayY: 0.1, displayZ: 2.0,
        sizeXM: 6.0, sizeYM: 4.0, sizeZM: 2.8
    )
    #expect(abs(s.sM - 0.5) < 1e-9)
    #expect(abs(s.zM - 1.5) < 1e-9)

    // On xMin (s along Y): computation (0, 2.5, 0.9)
    // → display = (−3, 0.9−1.4, −2.5+2) = (−3, −0.5, −0.5).
    let t = PlacementGeometry.wallSurface(
        wall: .xMin,
        displayX: -3.0, displayY: -0.5, displayZ: -0.5,
        sizeXM: 6.0, sizeYM: 4.0, sizeZM: 2.8
    )
    #expect(abs(t.sM - 2.5) < 1e-9)
    #expect(abs(t.zM - 0.9) < 1e-9)
}

@Test func floorSurfaceGivesComputationXY() {
    // Floor at computation (0.5, 0.8, ~0): display = (−2.5, −1.4, 1.2).
    let f = PlacementGeometry.floorSurface(
        displayX: -2.5, displayY: -1.4, displayZ: 1.2,
        sizeXM: 6.0, sizeYM: 4.0, sizeZM: 2.8
    )
    #expect(abs(f.xM - 0.5) < 1e-9)
    #expect(abs(f.yM - 0.8) < 1e-9)
}

@Test func windowPatchCentresAndClampsOnWall() {
    // Centred tap: 1.5 × 1.3 around (s=3, z=1.55).
    let centre = PlacementGeometry.windowPatch(
        on: .yMin, sM: 3.0, zM: 1.55,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 2.8
    )
    #expect(centre == WallPatchScene(wall: .yMin, s0M: 2.25, s1M: 3.75, z0M: 0.9, z1M: 2.2))

    // Tap off the low end: z clamps to the floor edge.
    let lowTap = PlacementGeometry.windowPatch(
        on: .yMin, sM: 3.0, zM: -1.0,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 2.8
    )
    #expect(abs(lowTap!.z0M) < 1e-9)

    // Tap near the corner: s clamps to the wall edge.
    let cornerTap = PlacementGeometry.windowPatch(
        on: .yMin, sM: 0.1, zM: 1.55,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 2.8
    )
    #expect(abs(cornerTap!.s0M) < 1e-9)

    // A wall too short for 1.5 m refuses rather than squeezing.
    let narrow = PlacementGeometry.windowPatch(
        on: .xMin, sM: 0.6, zM: 1.55,
        sizeXM: 6.0, sizeYM: 1.2, sizeZM: 2.8
    )
    #expect(narrow == nil)

    // A room too low for 1.3 m refuses.
    let lowRoom = PlacementGeometry.windowPatch(
        on: .yMin, sM: 3.0, zM: 0.4,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 1.0
    )
    #expect(lowRoom == nil)
}

@Test func doorPatchStandsOnFloorRegardlessOfTapHeight() {
    let door = PlacementGeometry.doorPatch(
        on: .yMax, sM: 3.0,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 2.8
    )
    #expect(door == WallPatchScene(wall: .yMax, s0M: 2.55, s1M: 3.45, z0M: 0.0, z1M: 2.1))

    // A room lower than the 2.1 m leaf refuses.
    let low = PlacementGeometry.doorPatch(
        on: .yMax, sM: 3.0,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 1.9
    )
    #expect(low == nil)
}

@Test func terminalPatchesKeepDeviceSizes() {
    // Supply 0.5 × 0.18, return 0.6 × 0.20 — same as the default split AC.
    let supply = PlacementGeometry.supplyPatch(
        on: .xMin, sM: 3.0, zM: 2.57,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 2.8
    )
    #expect(abs(supply!.s1M - supply!.s0M - 0.5) < 1e-9)
    #expect(abs(supply!.z1M - supply!.z0M - 0.18) < 1e-9)

    let ret = PlacementGeometry.returnPatch(
        on: .xMin, sM: 3.0, zM: 1.95,
        sizeXM: 6.0, sizeYM: 6.0, sizeZM: 2.8
    )
    #expect(abs(ret!.s1M - ret!.s0M - 0.6) < 1e-9)
    #expect(abs(ret!.z1M - ret!.z0M - 0.2) < 1e-9)
}

@Test func seatPositionClampsToWallMarginAtSampleHeight() {
    let pos = PlacementGeometry.seatPosition(xM: 0.05, yM: 5.95, sizeXM: 6.0, sizeYM: 6.0)
    #expect(abs(pos.x - 0.3) < 1e-9)
    #expect(abs(pos.y - 5.7) < 1e-9)
    #expect(abs(pos.z - 1.1) < 1e-9)
}
