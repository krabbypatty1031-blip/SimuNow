import Foundation
import SimuCore

/// Wall patch span in the wall-local convention the draft owns: `s` runs
/// along Y on xMin/xMax walls and along X on yMin/yMax walls; z is height.
/// These are display data, not solver input; no quality is implied.
public struct WallPatchScene: Equatable, Sendable {
    public var wall: WallFace
    public var s0M: Double
    public var s1M: Double
    public var z0M: Double
    public var z1M: Double

    public init(wall: WallFace, s0M: Double, s1M: Double, z0M: Double, z1M: Double) {
        self.wall = wall
        self.s0M = s0M
        self.s1M = s1M
        self.z0M = z0M
        self.z1M = z1M
    }

    public var patchAreaM2: Double {
        max(0, s1M - s0M) * max(0, z1M - z0M)
    }
}

/// Furniture box in computation metres (Z-up). Same origin/size as the
/// draft obstacle; the stored id stays on the model. `kind` drives the
/// schematic shape only — physics sees one blocked box either way.
public struct FurnitureScene: Equatable, Identifiable, Sendable {
    public var id: String
    public var origin: Position3D
    public var size: Position3D
    public var kind: FurnitureKind
    public var displayName: String

    public init(id: String, origin: Position3D, size: Position3D, kind: FurnitureKind, displayName: String) {
        self.id = id
        self.origin = origin
        self.size = size
        self.kind = kind
        self.displayName = displayName
    }
}

/// Seat marker in computation metres (Z-up, seat head height). The 3D view
/// draws a chair and seated figure here; it is not a second heat source
/// and not a comfort verdict.
public struct SeatScene: Equatable, Identifiable, Sendable {
    public var id: String
    public var position: Position3D
    /// Room-language name. The stored id stays on the model.
    public var displayName: String

    public init(id: String, position: Position3D, displayName: String? = nil) {
        self.id = id
        self.position = position
        self.displayName = displayName ?? id
    }
}

/// Real draft geometry for the viewport: room box, wall openings, air
/// terminals and seats. A draft without geometry has no honest box to
/// draw, so the scene is nil and the viewport keeps its empty state - a
/// fake room is never rendered.
public struct RoomScene: Equatable, Sendable {
    public var sizeXM: Double
    public var sizeYM: Double
    public var sizeZM: Double
    public var windows: [WallPatchScene]
    public var doors: [WallPatchScene]
    public var supply: WallPatchScene?
    public var returnAir: WallPatchScene?
    public var furniture: [FurnitureScene]
    public var seats: [SeatScene]
    /// Same order as `seats`. Used by VoiceOver and on-canvas labels.
    public var seatDisplayNames: [String] { seats.map(\.displayName) }

    public init?(
        draft: ProjectDraft,
        copy: UserFacingCopy = .english
    ) {
        guard let geometry = draft.geometry else {
            return nil
        }
        sizeXM = geometry.sizeX.value
        sizeYM = geometry.sizeY.value
        sizeZM = geometry.sizeZ.value
        windows = geometry.openings.filter { $0.kind == .window }.map(Self.patch)
        doors = geometry.openings.filter { $0.kind == .door }.map(Self.patch)
        supply = draft.hvac.map { Self.patch($0.supply) }
        returnAir = draft.hvac.map { Self.patch($0.returnTerminal) }
        // Numbering runs within each kind (桌子 1, 椅子 1, ...) so the label
        // names what the user placed. Kinds older files lack decode as desks.
        var kindCounts: [FurnitureKind: Int] = [:]
        furniture = geometry.obstacles.map { box in
            let index = kindCounts[box.kind, default: 0]
            kindCounts[box.kind] = index + 1
            return FurnitureScene(
                id: box.id,
                origin: box.origin,
                size: box.size,
                kind: box.kind,
                displayName: copy.furnitureTitle(kind: box.kind, index: index)
            )
        }
        let draftSeats = draft.occupancy?.seats ?? []
        seats = draftSeats.map { seat in
            SeatScene(
                id: seat.id,
                position: seat.position,
                displayName: copy.seatTitle(seat: seat, seats: draftSeats, geometry: geometry)
            )
        }
    }

    /// Draft opening/terminal spans map one-to-one; no invented geometry.
    private static func patch(_ opening: Opening) -> WallPatchScene {
        WallPatchScene(
            wall: opening.wall,
            s0M: opening.s0.value,
            s1M: opening.s1.value,
            z0M: opening.z0.value,
            z1M: opening.z1.value
        )
    }

    private static func patch(_ terminal: AirTerminal) -> WallPatchScene {
        WallPatchScene(
            wall: terminal.wall,
            s0M: terminal.s0.value,
            s1M: terminal.s1.value,
            z0M: terminal.z0.value,
            z1M: terminal.z1.value
        )
    }

    /// Four computation-frame corners of a wall patch rectangle, following
    /// the same s-along-face convention as `RoomGeometry.span(along:)`.
    public func patchCorners(_ patch: WallPatchScene) -> [Position3D] {
        let s0 = patch.s0M
        let s1 = patch.s1M
        let z0 = patch.z0M
        let z1 = patch.z1M
        switch patch.wall {
        case .xMin:
            // x = 0 face; s runs along Y.
            return [(0, s0, z0), (0, s1, z0), (0, s1, z1), (0, s0, z1)].map(Position3D.init)
        case .xMax:
            // x = sizeX face; s runs along Y.
            return [(sizeXM, s0, z0), (sizeXM, s1, z0), (sizeXM, s1, z1), (sizeXM, s0, z1)].map(Position3D.init)
        case .yMin:
            // y = 0 face; s runs along X.
            return [(s0, 0, z0), (s1, 0, z0), (s1, 0, z1), (s0, 0, z1)].map(Position3D.init)
        case .yMax:
            // y = sizeY face; s runs along X.
            return [(s0, sizeYM, z0), (s1, sizeYM, z0), (s1, sizeYM, z1), (s0, sizeYM, z1)].map(Position3D.init)
        }
    }

    /// Eight computation-frame corners of the room box.
    public var roomCorners: [Position3D] {
        [(0, 0, 0), (sizeXM, 0, 0), (sizeXM, sizeYM, 0), (0, sizeYM, 0),
         (0, 0, sizeZM), (sizeXM, 0, sizeZM), (sizeXM, sizeYM, sizeZM), (0, sizeYM, sizeZM)]
            .map(Position3D.init)
    }

    /// Room box edges as corner index pairs for wireframe drawing.
    public static let roomEdgeIndices: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 0),   // floor ring
        (4, 5), (5, 6), (6, 7), (7, 4),   // ceiling ring
        (0, 4), (1, 5), (2, 6), (3, 7),   // verticals
    ]

    /// VoiceOver reads the real parts; no metric value is claimed here.
    public func accessibilitySummary(copy: UserFacingCopy = .english) -> String {
        var parts: [String] = []
        parts.append(copy.roomSizeAccessibility(
            x: formatMetres(sizeXM),
            y: formatMetres(sizeYM),
            z: formatMetres(sizeZM)
        ))
        if !windows.isEmpty {
            parts.append(copy.windowCount(windows.count))
        }
        if !doors.isEmpty {
            parts.append(copy.doorCount(doors.count))
        }
        if !furniture.isEmpty {
            parts.append(copy.furnitureCount(furniture.count))
        }
        if supply != nil {
            parts.append(copy.terminalTitle(isSupply: true))
        }
        if returnAir != nil {
            parts.append(copy.terminalTitle(isSupply: false))
        }
        if seats.isEmpty {
            parts.append(copy.noSeatsYet)
        } else {
            parts.append(seats.map(\.displayName).joined(separator: copy.listSeparator))
        }
        return parts.joined(separator: copy.language == .chinese ? "，" : ", ")
    }

    public var accessibilitySummary: String {
        accessibilitySummary(copy: .english)
    }

    private func formatMetres(_ value: Double) -> String {
        UserFacingCopy.displayNumber(value)
    }
}
