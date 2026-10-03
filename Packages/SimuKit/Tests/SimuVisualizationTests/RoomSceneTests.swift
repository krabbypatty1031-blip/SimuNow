import Foundation
import Testing
import SimuCore
import SimuVisualization

// P4-05a: the viewport draws the real draft geometry - room box, windows,
// supply/return terminals and seats - and never invents a room when the
// model is incomplete. Computation Z-up metres reach the screen through
// CoordinateMapping, the one place that owns the axis convention.

@Test func roomSceneCarriesDraftGeometry() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    #expect(scene.sizeXM == 6)
    #expect(scene.sizeYM == 6)
    #expect(scene.sizeZM == 2.8)
    #expect(scene.windows.count == 1)
    #expect(scene.doors.isEmpty)
    #expect(scene.supply != nil)
    #expect(scene.returnAir != nil)
    #expect(scene.seats.count == 4)
    #expect(scene.seats.map(\.id) == ["S1", "S2", "S3", "S4"])
}

@Test func roomSceneMapsWallPatchLocalSpansOntoFaces() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    // The template window sits on the xMax wall with local s along Y.
    let window = try #require(scene.windows.first)
    #expect(window.wall == .xMax)
    #expect(window.s0M >= 0 && window.s1M <= scene.sizeYM)
    #expect(window.z0M >= 0 && window.z1M <= scene.sizeZM)
    #expect(window.s0M < window.s1M)
    #expect(window.z0M < window.z1M)
    // Terminals are patch spans on the wall, not point positions.
    let supply = try #require(scene.supply)
    #expect(supply.patchAreaM2 > 0)
    let returnAir = try #require(scene.returnAir)
    #expect(returnAir.patchAreaM2 > 0)
}

@Test func roomSceneKeepsSeatsInComputationFrame() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    // Seat positions stay in computation metres (Z-up, seat head height).
    for seat in scene.seats {
        #expect(seat.position.z > 0)
        #expect(seat.position.z < scene.sizeZM)
        #expect(seat.position.x > 0 && seat.position.x < scene.sizeXM)
        #expect(seat.position.y > 0 && seat.position.y < scene.sizeYM)
    }
}

@Test func incompleteModelProducesNoRoomScene() throws {
    // A draft without geometry has no honest room box to draw.
    var draft = try ProjectTemplates.bundled(named: "office").project
    draft.geometry = nil
    #expect(RoomScene(draft: draft) == nil)

    // No draft at all means no scene; the viewport shows its empty state.
    let empty = ProjectDraft(id: UUID(), name: "empty", spaceType: .office)
    #expect(RoomScene(draft: empty) == nil)
}

@Test func projectionMapsComputationZUpThroughDisplayFrame() {
    // The projection consumes CoordinateMapping: computation Z-up goes in,
    // screen points come out. At yaw 0 a higher computation z must land
    // higher on screen (smaller y), and a larger computation x must land
    // further right.
    let projection = IsometricProjection(yawRadians: 0, pitchRadians: .pi / 6)
    let lowFloor = projection.screenPoint(Position3D(x: 1, y: 1, z: 0))
    let seatHeight = projection.screenPoint(Position3D(x: 1, y: 1, z: 1.1))
    #expect(seatHeight.y < lowFloor.y)

    let westSeat = projection.screenPoint(Position3D(x: 1, y: 1, z: 1.1))
    let eastSeat = projection.screenPoint(Position3D(x: 5, y: 1, z: 1.1))
    #expect(eastSeat.x > westSeat.x)
}

@Test func projectionKeepsRoomInsideItsBounds() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let projection = IsometricProjection(yawRadians: -0.5, pitchRadians: .pi / 6)
    // Every room corner stays inside a bounding square around the origin.
    let corners = projection.roomCorners(scene)
    #expect(corners.count == 8)
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    #expect((xs.max() ?? 0) - (xs.min() ?? 0) < 20)
    #expect((ys.max() ?? 0) - (ys.min() ?? 0) < 20)
    #expect(xs.max()! > xs.min()!)
    #expect(ys.max()! > ys.min()!)
}

@testable import SimuVisualization
@Test func roomSceneAccessibilitySummaryNamesRealParts() throws {
    let draft = try ProjectTemplates.bundled(named: "office").project
    let scene = try #require(RoomScene(draft: draft))
    let summary = scene.accessibilitySummary
    #expect(summary.contains("6"))
    #expect(summary.contains("窗"))
    #expect(summary.contains("座位"))
    #expect(summary.contains("出风"))
    #expect(summary.contains("回风"))
    #expect(!summary.contains("S1"))
    #expect(scene.seatDisplayNames.contains(where: { $0.contains("靠窗") }))
    for name in scene.seatDisplayNames {
        #expect(name != "S1")
        #expect(!name.hasPrefix("S"))
    }
}
