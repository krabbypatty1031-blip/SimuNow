import Foundation
import SimuCore

/// Viewport tap placement: converts a RealityKit hit in root-local display
/// metres back into draft coordinates (wall-local s/z, or floor x/y), and
/// holds the default patch shapes so a tap places the same size the
/// inspector's add-buttons do. Pure geometry, unit-tested without entities.
///
/// The conversion inverts `RoomDisplayLayout.centeredDisplay`:
/// display = toDisplay(computation) − toDisplay(room centre), where
/// `toDisplay` maps computation (x, y, z) to display (x, z, −y)
/// (`CoordinateMapping`, Y-up display metres).
public enum PlacementGeometry: Sendable {
    /// Root-local entity names. The builder names its collision boxes this
    /// way so the tap handler can tell which face was hit.
    public static let floorEntityName = "placement.floor"

    public static func wallEntityName(_ wall: WallFace) -> String {
        "placement.wall.\(wall.rawValue)"
    }

    /// The draft face a tap resolved to. Carries no quality and no result.
    public enum Surface: Equatable, Sendable {
        /// Wall-local `s` along the face (metres from the wall's minimum
        /// plan coordinate) and height `z`, the same convention as `Opening`.
        case wall(WallFace, sM: Double, zM: Double)
        /// Computation-frame floor position (Z-up metres).
        case floor(xM: Double, yM: Double)
    }

    // MARK: display metres → draft coordinates

    /// Inverse of `centeredDisplay` for one point. Takes plain sizes so the
    /// math is testable without a `RoomScene`.
    public static func computationFromDisplay(
        displayX: Double,
        displayY: Double,
        displayZ: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> Position3D {
        // display = (c.x − sizeX/2, c.z − sizeZ/2, −c.y + sizeY/2); solve for c.
        Position3D(
            x: displayX + sizeXM / 2,
            y: sizeYM / 2 - displayZ,
            z: displayY + sizeZM / 2
        )
    }

    /// A tap on a named wall box: s runs along Y on xMin/xMax walls and
    /// along X on yMin/yMax walls (`RoomGeometry.span(along:)` convention);
    /// z is the height. The hit may land on the box's outer side or end
    /// faces — s/z are clamped by the patch builders, not here.
    public static func wallSurface(
        wall: WallFace,
        displayX: Double,
        displayY: Double,
        displayZ: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> (sM: Double, zM: Double) {
        let c = computationFromDisplay(
            displayX: displayX,
            displayY: displayY,
            displayZ: displayZ,
            sizeXM: sizeXM,
            sizeYM: sizeYM,
            sizeZM: sizeZM
        )
        let s: Double
        switch wall {
        case .xMin, .xMax: s = c.y
        case .yMin, .yMax: s = c.x
        }
        return (s, c.z)
    }

    /// A tap on the floor box: computation x/y.
    public static func floorSurface(
        displayX: Double,
        displayY: Double,
        displayZ: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> (xM: Double, yM: Double) {
        let c = computationFromDisplay(
            displayX: displayX,
            displayY: displayY,
            displayZ: displayZ,
            sizeXM: sizeXM,
            sizeYM: sizeYM,
            sizeZM: sizeZM
        )
        return (c.x, c.y)
    }

    // MARK: default patch shapes

    /// Default sizes match the inspector add-button semantics: a window is
    /// 1.5 × 1.3 m centred on the tap, a door 0.9 × 2.1 m standing on the
    /// floor at the tapped s, terminals keep the split-AC device sizes.
    public static let windowWidthM = 1.5
    public static let windowHeightM = 1.3
    public static let doorWidthM = 0.9
    public static let doorHeightM = 2.1
    public static let supplyWidthM = 0.5
    public static let supplyHeightM = 0.18
    public static let returnWidthM = 0.6
    public static let returnHeightM = 0.20

    /// Centre-clamped patch on the tapped wall. Returns nil when the wall is
    /// too short or the room too low for the default size — a squeezed
    /// patch is never invented silently.
    static func clampedPatch(
        on wall: WallFace,
        sM: Double,
        zM: Double,
        width: Double,
        height: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double,
        z0Floor: Bool
    ) -> WallPatchScene? {
        let span: Double
        switch wall {
        case .xMin, .xMax: span = sizeYM
        case .yMin, .yMax: span = sizeXM
        }
        guard width <= span, height <= sizeZM, width > 0, height > 0 else {
            return nil
        }
        // Clamp the centre so the whole rectangle stays on the face.
        let sCenter = min(max(sM, width / 2), span - width / 2)
        let zCenter = z0Floor
            ? height / 2  // doors stand on the floor regardless of tap height
            : min(max(zM, height / 2), sizeZM - height / 2)
        return WallPatchScene(
            wall: wall,
            s0M: sCenter - width / 2,
            s1M: sCenter + width / 2,
            z0M: zCenter - height / 2,
            z1M: zCenter + height / 2
        )
    }

    /// Window patch centred on the tap. Same default size as the inspector
    /// add-button; the 80 W/m² flux is written by the store, not here.
    public static func windowPatch(
        on wall: WallFace,
        sM: Double,
        zM: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> WallPatchScene? {
        clampedPatch(
            on: wall, sM: sM, zM: zM,
            width: windowWidthM, height: windowHeightM,
            sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM,
            z0Floor: false
        )
    }

    /// Door patch standing on the floor at the tapped s.
    public static func doorPatch(
        on wall: WallFace,
        sM: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> WallPatchScene? {
        clampedPatch(
            on: wall, sM: sM, zM: 0,
            width: doorWidthM, height: doorHeightM,
            sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM,
            z0Floor: true
        )
    }

    /// Supply-terminal patch centred on the tap (split-AC device size).
    public static func supplyPatch(
        on wall: WallFace,
        sM: Double,
        zM: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> WallPatchScene? {
        clampedPatch(
            on: wall, sM: sM, zM: zM,
            width: supplyWidthM, height: supplyHeightM,
            sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM,
            z0Floor: false
        )
    }

    /// Return-terminal patch centred on the tap (return-grille size).
    public static func returnPatch(
        on wall: WallFace,
        sM: Double,
        zM: Double,
        sizeXM: Double,
        sizeYM: Double,
        sizeZM: Double
    ) -> WallPatchScene? {
        clampedPatch(
            on: wall, sM: sM, zM: zM,
            width: returnWidthM, height: returnHeightM,
            sizeXM: sizeXM, sizeYM: sizeYM, sizeZM: sizeZM,
            z0Floor: false
        )
    }

    /// Seat sample position from a floor tap: z is the 1.1 m sample height
    /// (`nextSeatPosition`), the x/y are clamped to a 0.3 m wall margin.
    public static func seatPosition(xM: Double, yM: Double, sizeXM: Double, sizeYM: Double) -> Position3D {
        func clamp(_ value: Double, _ size: Double) -> Double {
            min(max(value, 0.3), max(size - 0.3, 0.3))
        }
        return Position3D(x: clamp(xM, sizeXM), y: clamp(yM, sizeYM), z: 1.1)
    }
}
