import Foundation
import Testing
import SimuCore
import SimuVisualization

@Test func roomDisplayLayoutMapsComputationBoxOntoYUpExtents() {
    // RealityKit boxes are Y-up: height is computation Z, depth is computation Y.
    let extents = RoomDisplayLayout.displayBoxExtents(size: Position3D(x: 1.2, y: 0.6, z: 0.75))
    #expect(abs(extents.width - 1.2) < 1e-5)
    #expect(abs(extents.height - 0.75) < 1e-5)
    #expect(abs(extents.depth - 0.6) < 1e-5)
}

@Test func roomDisplayLayoutCentersFurnitureInTheRoom() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    draft.geometry?.obstacles = [
        ObstacleBox(id: "F1", origin: Position3D(x: 1, y: 2, z: 0), size: Position3D(x: 1.2, y: 0.6, z: 0.8)),
    ]
    let scene = try #require(RoomScene(draft: draft))
    let furniture = try #require(scene.furniture.first)
    let center = Position3D(
        x: furniture.origin.x + furniture.size.x / 2,
        y: furniture.origin.y + furniture.size.y / 2,
        z: furniture.origin.z + furniture.size.z / 2
    )
    let display = RoomDisplayLayout.centeredDisplay(center, scene: scene)
    // Room centre is (3, 3, 1.4); furniture centre is (1.6, 2.3, 0.4).
    // Display = (x, z, -y) minus the room-centre display.
    #expect(abs(display.x + 1.4) < 1e-5)
    #expect(abs(display.y + 1.0) < 1e-5)
    #expect(abs(display.z - 0.7) < 1e-5)
}

@Test func roomDisplayLayoutInwardFacingPointsIntoTheRoom() {
    // Display = (x, z, −y). Computation +X stays +X; computation +Y becomes −Z.
    let xMin = RoomDisplayLayout.inwardDisplayFacing(.xMin)
    #expect(xMin.x == 1 && xMin.y == 0 && xMin.z == 0)
    let xMax = RoomDisplayLayout.inwardDisplayFacing(.xMax)
    #expect(xMax.x == -1 && xMax.y == 0 && xMax.z == 0)
    let yMin = RoomDisplayLayout.inwardDisplayFacing(.yMin)
    #expect(yMin.x == 0 && yMin.y == 0 && yMin.z == -1)
    let yMax = RoomDisplayLayout.inwardDisplayFacing(.yMax)
    #expect(yMax.x == 0 && yMax.y == 0 && yMax.z == 1)
}

@Test func roomDisplayLayoutSeatFloorDropsHeadHeightToTheFloor() {
    // Seat z is the comfort sample (1.1 m). The chair and person stand on z = 0.
    let seat = SeatScene(id: "S1", position: Position3D(x: 1.5, y: 4.5, z: 1.1), displayName: "座位")
    let floor = RoomDisplayLayout.seatFloor(seat)
    #expect(floor.x == 1.5)
    #expect(floor.y == 4.5)
    #expect(floor.z == 0)
}

@Test func roomDisplayLayoutPatchPlacementKeepsTheOfficeWindowOnXMax() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let window = try #require(scene.windows.first)
    let placed = RoomDisplayLayout.patchPlacement(window, scene: scene, outward: 0.03)
    #expect(abs(placed.center.x - (scene.sizeXM + 0.03)) < 1e-9)
    #expect(abs(placed.center.y - (window.s0M + window.s1M) / 2) < 1e-9)
    #expect(abs(placed.center.z - (window.z0M + window.z1M) / 2) < 1e-9)
    #expect(abs(placed.size.y - (window.s1M - window.s0M)) < 1e-9)
    #expect(abs(placed.size.z - (window.z1M - window.z0M)) < 1e-9)
}

@Test func roomDisplayLayoutBuildIDChangesWhenTheUserAddsMovesOrRemovesObjects() throws {
    var draft = try ProjectTemplates.bundled(named: "office").project
    let before = RoomDisplayLayout.buildID(
        scene: try #require(RoomScene(draft: draft)),
        fieldHash: nil,
        paletteKey: nil
    )

    draft.geometry?.obstacles = [
        ObstacleBox(id: "F1", origin: Position3D(x: 1, y: 1, z: 0), size: Position3D(x: 1.2, y: 0.7, z: 0.75)),
    ]
    let withDesk = RoomDisplayLayout.buildID(
        scene: try #require(RoomScene(draft: draft)),
        fieldHash: nil,
        paletteKey: nil
    )
    #expect(withDesk != before)
    #expect(withDesk.contains("F1"))

    draft.removeOpening(id: "W1")
    let noWindow = RoomDisplayLayout.buildID(
        scene: try #require(RoomScene(draft: draft)),
        fieldHash: nil,
        paletteKey: nil
    )
    #expect(noWindow != withDesk)
    #expect(!noWindow.contains("w0:"))

    draft = try ProjectTemplates.bundled(named: "office").project
    var occupancy = try #require(draft.occupancy)
    occupancy.seats[0].position.x = 2.2
    draft.occupancy = occupancy
    let movedSeat = RoomDisplayLayout.buildID(
        scene: try #require(RoomScene(draft: draft)),
        fieldHash: nil,
        paletteKey: nil
    )
    #expect(movedSeat != before)
    #expect(movedSeat.contains("2.20000"))

    draft.removeHVAC()
    let noAC = RoomDisplayLayout.buildID(
        scene: try #require(RoomScene(draft: draft)),
        fieldHash: nil,
        paletteKey: nil
    )
    #expect(noAC != movedSeat)
    #expect(!noAC.contains("sup:"))
}

@Test func roomDisplayLayoutMapsComputationVelocityOntoDisplayAxes() {
    // Display = (x, z, −y), same as a position so arrows stay honest to the field.
    let plusX = RoomDisplayLayout.displayVelocity(ux: 0.2, uy: 0, uz: 0)
    #expect(abs(plusX.x - 0.2) < 1e-6 && plusX.y == 0 && plusX.z == 0)
    let plusY = RoomDisplayLayout.displayVelocity(ux: 0, uy: 0.3, uz: 0)
    #expect(plusY.x == 0 && plusY.y == 0 && abs(plusY.z + 0.3) < 1e-6)
}

@Test func roomDisplayLayoutGlyphLengthIsADisplayScale() {
    #expect(abs(RoomDisplayLayout.glyphDisplayLength(mag: 0.2, maxMag: 0.2) - 0.38) < 1e-5)
    #expect(abs(RoomDisplayLayout.glyphDisplayLength(mag: 0, maxMag: 0.2) - 0.12) < 1e-5)
    #expect(RoomDisplayLayout.glyphDisplayLength(mag: 0.03, maxMag: 0.03) > 0.3)
}

@Test func polylineSampleWalksArcLengthAndWraps() {
    let points = [
        Position3D(x: 0, y: 0, z: 1.1),
        Position3D(x: 2, y: 0, z: 1.1),
        Position3D(x: 2, y: 2, z: 1.1),
    ]
    let start = RoomDisplayLayout.polylineSample(points: points, phase: 0)
    let mid = RoomDisplayLayout.polylineSample(points: points, phase: 0.5)
    let end = RoomDisplayLayout.polylineSample(points: points, phase: 1)
    let wrapped = RoomDisplayLayout.polylineSample(points: points, phase: 1.25)
    #expect(start.map { abs($0.x) < 1e-9 && abs($0.y) < 1e-9 } == true)
    #expect(mid.map { abs($0.x - 2) < 1e-9 && abs($0.y) < 1e-9 } == true)
    #expect(end.map { abs($0.x) < 1e-9 && abs($0.y) < 1e-9 } == true)
    #expect(wrapped.map { abs($0.x - 1) < 1e-9 && abs($0.y) < 1e-9 } == true)
    #expect(RoomDisplayLayout.polylineSample(points: [points[0]], phase: 0.3) == nil)
}

@Test func solvedBandPatchSpansTheFullWallAtTheTerminalHeights() throws {
    // The solver breathes through a full-span band at the terminal heights;
    // the schematic AC box marks the device, not the mesh inlet.
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let supply = try #require(scene.supply)
    let band = RoomDisplayLayout.solvedBandPatch(supply, scene: scene)
    #expect(band.wall == supply.wall)
    #expect(band.s0M == 0)
    #expect(abs(band.s1M - scene.sizeYM) < 1e-9)
    #expect(band.z0M == supply.z0M && band.z1M == supply.z1M)
    // Placement covers the whole wall span at the same height range.
    let placed = RoomDisplayLayout.patchPlacement(band, scene: scene, outward: -0.02)
    #expect(abs(placed.center.y - scene.sizeYM / 2) < 1e-9)
    #expect(abs(placed.size.y - scene.sizeYM) < 1e-9)
    #expect(abs(placed.size.z - (supply.z1M - supply.z0M)) < 1e-9)
    // A y-wall terminal spans the x extent instead.
    let yBand = RoomDisplayLayout.solvedBandPatch(
        WallPatchScene(wall: .yMin, s0M: 1, s1M: 2, z0M: 1, z1M: 2),
        scene: scene
    )
    #expect(yBand.s0M == 0)
    #expect(abs(yBand.s1M - scene.sizeXM) < 1e-9)
}

@Test func terminalLabelAnchorSitsBesideAndInFrontOfTheDevice() throws {
    // The 0.20 m AC body swallows a label at the band midpoint; the
    // words have to sit past the box, into the room, and above the lid.
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let supply = try #require(scene.supply)
    let anchor = RoomDisplayLayout.terminalLabelAnchor(supply, scene: scene)
    #expect(anchor.x >= 0.30)
    #expect(anchor.y > supply.s1M)
    #expect(anchor.z > supply.z1M)
    let returnAir = try #require(scene.returnAir)
    let returnAnchor = RoomDisplayLayout.terminalLabelAnchor(returnAir, scene: scene)
    #expect(returnAnchor.x >= 0.30)
    #expect(returnAnchor.y > returnAir.s1M)
    #expect(returnAnchor.z > returnAir.z1M)
    #expect(abs(returnAnchor.z - anchor.z) > 0.3)
}

@Test func flowParticlePhaseIsADisplayLoopNotPhysicalTime() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let oneLap = Date(timeIntervalSinceReferenceDate: RoomDisplayLayout.flowParticleLoopSeconds)
    let half = Date(timeIntervalSinceReferenceDate: RoomDisplayLayout.flowParticleLoopSeconds / 2)
    #expect(abs(RoomDisplayLayout.flowParticlePhase(at: start)) < 1e-9)
    #expect(abs(RoomDisplayLayout.flowParticlePhase(at: oneLap)) < 1e-9)
    #expect(abs(RoomDisplayLayout.flowParticlePhase(at: half) - 0.5) < 1e-9)
    #expect(RoomDisplayLayout.flowParticleLoopSeconds < 10)
    #expect(RoomDisplayLayout.flowBeadPhase(clock: 0, index: 0, count: 4) == 0)
    #expect(abs(RoomDisplayLayout.flowBeadPhase(clock: 0, index: 1, count: 4) - 0.25) < 1e-9)
    #expect(abs(RoomDisplayLayout.flowBeadPhase(clock: 0.75, index: 1, count: 4)) < 1e-9)
}

@Test func roomDisplayLayoutBuildIDChangesWhenFlowOverlayArrives() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let before = RoomDisplayLayout.buildID(scene: scene, fieldHash: nil, paletteKey: nil)
    let after = RoomDisplayLayout.buildID(scene: scene, fieldHash: nil, paletteKey: nil, flowHash: "flow-1")
    #expect(after != before)
    #expect(after.contains("flow-1"))
}

@Test func roomDisplayLayoutSlicePlaneUsesCellCentres() throws {
    let field = FieldSlice(
        zM: 1.1,
        originM: FieldSlice.SliceOrigin(x: 0.1, y: 0.1),
        spacingM: FieldSlice.SliceOrigin(x: 0.25, y: 0.25),
        shape: FieldSlice.SliceShape(nx: 2, ny: 2),
        values: [[25.0, 25.1], [25.2, 25.3]],
        valid: [[true, true], [true, true]],
        stats: FieldSlice.SliceStats(validCount: 4, minC: 25.0, maxC: 25.3),
        inputHash: "plane"
    )
    let plane = try #require(RoomDisplayLayout.slicePlane(field: field))
    #expect(abs(plane.width - 0.5) < 1e-6)
    #expect(abs(plane.depth - 0.5) < 1e-6)
    #expect(abs(plane.center.x - 0.225) < 1e-9)
    #expect(abs(plane.center.y - 0.225) < 1e-9)
    #expect(abs(plane.center.z - 1.1) < 1e-9)
}

@Test func roomEnvelopePaletteKeepsWallsAndEdgesVisibleOnLightAndDark() {
    // Light walls must be darker than the current near-white 0.72 fill or they
    // vanish on a white canvas. Dark walls stay pale so they still read on black.
    let light = RoomDisplayLayout.envelopePalette(appearance: .light)
    let dark = RoomDisplayLayout.envelopePalette(appearance: .dark)
    #expect(light.wallRed < 0.55)
    #expect(light.wallBlendOpacity >= 0.45)
    #expect(light.edgeRed < 0.35)
    #expect(dark.wallRed > 0.65)
    #expect(dark.edgeRed > 0.75)
    #expect(light.edgeRadiusM > 0.01)
    #expect(abs(light.edgeRadiusM - dark.edgeRadiusM) < 1e-9)
}

@Test func roomEdgeSegmentsTraceTheOfficeBox() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let edges = RoomDisplayLayout.roomEdgeSegments(scene: scene)
    #expect(edges.count == 12)
    let floorRing = edges.filter { edge in
        edge.start.z == 0 && edge.end.z == 0
    }
    #expect(floorRing.count == 4)
    var verticalCount = 0
    for edge in edges where edge.start.x == edge.end.x && edge.start.y == edge.end.y {
        verticalCount += 1
    }
    #expect(verticalCount == 4)
    #expect(edges.contains { $0.lengthM > 5.9 })
}

@Test func roomDisplayLayoutBuildIDChangesWhenAppearanceSwitches() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let light = RoomDisplayLayout.buildID(
        scene: scene, fieldHash: nil, paletteKey: nil, appearanceKey: "light"
    )
    let dark = RoomDisplayLayout.buildID(
        scene: scene, fieldHash: nil, paletteKey: nil, appearanceKey: "dark"
    )
    #expect(light != dark)
    #expect(light.contains("light"))
}
