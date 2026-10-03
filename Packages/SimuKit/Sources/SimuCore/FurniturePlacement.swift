import Foundation

/// Furniture categories the user can place (user request 2026-10-04).
/// The kind drives the schematic drawing and the default footprint; the
/// physics treats every piece as one blocked box (disclosed in the case
/// assumptions), so kind never changes the solver input by itself.
public enum FurnitureKind: String, Codable, CaseIterable, Sendable, Equatable {
    case desk
    case chair
    case cabinet
    case screen

    /// Room-language label, same wording as the editor buttons.
    public var title: String {
        switch self {
        case .desk: return "桌子"
        case .chair: return "椅子"
        case .cabinet: return "柜子"
        case .screen: return "屏风"
        }
    }

    /// Default footprint in computation metres (Z-up): width × depth × height
    /// of the box the user starts from before editing.
    public var defaultSize: Position3D {
        switch self {
        case .desk: return Position3D(x: 1.2, y: 0.7, z: 0.75)
        case .chair: return Position3D(x: 0.5, y: 0.5, z: 0.9)
        case .cabinet: return Position3D(x: 0.8, y: 0.4, z: 1.8)
        case .screen: return Position3D(x: 1.6, y: 0.06, z: 1.7)
        }
    }
}

/// Placement legality for furniture: a box may land only inside the room
/// and clear of every other thing the simulation cares about. One pure
/// function shared by the editor, the drag preview and the engine intake,
/// so the UI and the solver can never disagree about what "legal" means.
public enum FurniturePlacement: Sendable, Equatable {
    /// Why a placement is refused. The wording reaches the user verbatim.
    public enum Rejection: String, Sendable, Equatable, CaseIterable {
        case outsideRoom = "家具必须完全放在房间内"
        case overlapsFurniture = "家具不能与其他家具重叠"
        case coversSeat = "家具不能压住座位"
        case blocksTerminal = "家具不能挡住送风口或回风口"
        case blocksWindow = "家具不能挡住窗户"
    }

    /// How far a wall patch (window, supply, return) reaches into the room
    /// for the overlap test: the innermost cell layer is what feeds the
    /// energy and mass gates, so furniture must stay clear of it.
    public static let wallClearanceM = 0.4

    /// Nil when the box may be placed; otherwise the reason it may not.
    /// `existing` skips a box's own id so an in-place edit never collides
    /// with itself.
    public static func rejection(
        for box: ObstacleBox,
        in draft: ProjectDraft,
        ignoring existingID: String? = nil
    ) -> Rejection? {
        guard let geometry = draft.geometry else {
            return .outsideRoom
        }
        // 1. Fully inside the room box.
        let maxX = box.origin.x + box.size.x
        let maxY = box.origin.y + box.size.y
        let maxZ = box.origin.z + box.size.z
        let sizeX = geometry.sizeX.value
        let sizeY = geometry.sizeY.value
        let sizeZ = geometry.sizeZ.value
        guard box.origin.x >= 0, box.origin.y >= 0, box.origin.z >= 0,
            maxX <= sizeX, maxY <= sizeY, maxZ <= sizeZ,
            box.size.x > 0, box.size.y > 0, box.size.z > 0 else {
            return .outsideRoom
        }
        // 2. Clear of every other furniture box.
        for other in geometry.obstacles where other.id != existingID {
            if intersects(box, other) {
                return .overlapsFurniture
            }
        }
        // 3. Clear of seats — a seat is a sampling point; a box on top of
        // it would put the sample inside a solid.
        for seat in draft.occupancy?.seats ?? [] {
            let p = seat.position
            if p.x >= box.origin.x, p.x <= maxX,
                p.y >= box.origin.y, p.y <= maxY,
                p.z >= box.origin.z, p.z <= maxZ {
                return .coversSeat
            }
        }
        // 4. Clear of the supply/return wall bands. The case writer stretches
        // each terminal to the FULL wall span at its z range (see
        // RoomDisplayLayout.solvedBandPatch), so the placement test uses the
        // same full-span band — a box in front of the grille anywhere along
        // the wall would remove inlet/outlet cells and break the mass gate.
        if let hvac = draft.hvac {
            for terminal in [hvac.supply, hvac.returnTerminal] {
                let wallSpan: Double
                switch terminal.wall {
                case .xMin, .xMax: wallSpan = sizeY
                case .yMin, .yMax: wallSpan = sizeX
                }
                if intersectsWallPatch(
                    box,
                    wall: terminal.wall,
                    s0: 0,
                    s1: wallSpan,
                    z0: terminal.z0.value,
                    z1: terminal.z1.value,
                    sizeX: sizeX,
                    sizeY: sizeY
                ) {
                    return .blocksTerminal
                }
            }
        }
        // 5. Clear of windows: the energy gate accounts window q×A on the
        // wall cells; furniture against a window removes them.
        for opening in geometry.openings where opening.kind == .window {
            if intersectsWallPatch(box, wall: opening.wall, s0: opening.s0.value, s1: opening.s1.value, z0: opening.z0.value, z1: opening.z1.value, sizeX: sizeX, sizeY: sizeY) {
                return .blocksWindow
            }
        }
        return nil
    }

    /// AABB overlap between two furniture boxes.
    static func intersects(_ a: ObstacleBox, _ b: ObstacleBox) -> Bool {
        a.origin.x < b.origin.x + b.size.x && b.origin.x < a.origin.x + a.size.x
            && a.origin.y < b.origin.y + b.size.y && b.origin.y < a.origin.y + a.size.y
            && a.origin.z < b.origin.z + b.size.z && b.origin.z < a.origin.z + a.size.z
    }

    /// Overlap between a box and the near-wall volume of a wall patch:
    /// the patch rectangle extruded `wallClearanceM` into the room.
    static func intersectsWallPatch(
        _ box: ObstacleBox,
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        sizeX: Double,
        sizeY: Double
    ) -> Bool {
        // The patch's span along the wall, and the depth range it owns.
        // `s` runs along the wall from its minimum plan coordinate.
        let clearance = wallClearanceM
        switch wall {
        case .xMin:
            // Wall at x = 0; owns 0...clearance in x, s runs along y.
            return box.origin.x < clearance
                && box.origin.y < s1 && s0 < box.origin.y + box.size.y
                && box.origin.z < z1 && z0 < box.origin.z + box.size.z
        case .xMax:
            // Wall at x = sizeX; owns sizeX - clearance...sizeX in x.
            return box.origin.x + box.size.x > sizeX - clearance
                && box.origin.y < s1 && s0 < box.origin.y + box.size.y
                && box.origin.z < z1 && z0 < box.origin.z + box.size.z
        case .yMin:
            // Wall at y = 0; owns 0...clearance in y, s runs along x.
            return box.origin.y < clearance
                && box.origin.x < s1 && s0 < box.origin.x + box.size.x
                && box.origin.z < z1 && z0 < box.origin.z + box.size.z
        case .yMax:
            // Wall at y = sizeY; owns sizeY - clearance...sizeY in y.
            return box.origin.y + box.size.y > sizeY - clearance
                && box.origin.x < s1 && s0 < box.origin.x + box.size.x
                && box.origin.z < z1 && z0 < box.origin.z + box.size.z
        }
    }
}
