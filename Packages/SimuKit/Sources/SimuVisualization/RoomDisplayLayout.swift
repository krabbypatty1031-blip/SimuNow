import Foundation
import SimuCore

/// Display-frame metres after `CoordinateMapping` (Y-up). Kept as plain
/// floats so layout can be tested without constructing RealityKit entities.
public struct DisplayMetres: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
}

public struct DisplayBoxExtents: Equatable, Sendable {
    public var width: Float
    public var height: Float
    public var depth: Float
}

public struct SlicePlaneLayout: Equatable, Sendable {
    public var width: Float
    public var depth: Float
    public var center: Position3D
}

/// Computation-frame centre and extents of a wall patch, optionally
/// offset off the face so a mesh does not z-fight the wall.
public struct PatchPlacement: Equatable, Sendable {
    public var center: Position3D
    public var size: Position3D
}

/// Geometry helpers shared by the RealityKit builder. Axis conversion stays
/// in `CoordinateMapping`; this type only sizes and recentres the room.
public enum RoomDisplayLayout: Sendable {
    /// RealityKit boxes are Y-up: height is computation Z, depth is computation Y.
    public static func displayBoxExtents(size: Position3D) -> DisplayBoxExtents {
        DisplayBoxExtents(width: Float(size.x), height: Float(size.z), depth: Float(size.y))
    }

    public static func roomCenter(scene: RoomScene) -> Position3D {
        Position3D(x: scene.sizeXM / 2, y: scene.sizeYM / 2, z: scene.sizeZM / 2)
    }

    /// Computation metres minus the room centre, then mapped to Y-up display.
    public static func centeredDisplay(_ computation: Position3D, scene: RoomScene) -> DisplayMetres {
        let display = CoordinateMapping.toDisplay(computation)
        let center = CoordinateMapping.toDisplay(roomCenter(scene: scene))
        return DisplayMetres(
            x: Float(display.x - center.x),
            y: Float(display.y - center.y),
            z: Float(display.z - center.z)
        )
    }

    /// Display-space unit vector pointing from the wall into the room.
    /// Computation +X stays display +X; computation +Y becomes display −Z.
    public static func inwardDisplayFacing(_ wall: WallFace) -> DisplayMetres {
        switch wall {
        case .xMin:
            return DisplayMetres(x: 1, y: 0, z: 0)
        case .xMax:
            return DisplayMetres(x: -1, y: 0, z: 0)
        case .yMin:
            return DisplayMetres(x: 0, y: 0, z: -1)
        case .yMax:
            return DisplayMetres(x: 0, y: 0, z: 1)
        }
    }

    /// Chair and person stand on the floor. Seat z is the 1.1 m sample, not a body height.
    public static func seatFloor(_ seat: SeatScene) -> Position3D {
        Position3D(x: seat.position.x, y: seat.position.y, z: 0)
    }

    /// Offset the patch off the wall. Negative `outward` moves the centre into the room.
    public static func patchPlacement(
        _ patch: WallPatchScene,
        scene: RoomScene,
        outward: Double
    ) -> PatchPlacement {
        let sMid = (patch.s0M + patch.s1M) / 2
        let zMid = (patch.z0M + patch.z1M) / 2
        let sSpan = max(patch.s1M - patch.s0M, 0.05)
        let zSpan = max(patch.z1M - patch.z0M, 0.05)
        let thickness = 0.04
        switch patch.wall {
        case .xMin:
            return PatchPlacement(
                center: Position3D(x: -outward, y: sMid, z: zMid),
                size: Position3D(x: thickness, y: sSpan, z: zSpan)
            )
        case .xMax:
            return PatchPlacement(
                center: Position3D(x: scene.sizeXM + outward, y: sMid, z: zMid),
                size: Position3D(x: thickness, y: sSpan, z: zSpan)
            )
        case .yMin:
            return PatchPlacement(
                center: Position3D(x: sMid, y: -outward, z: zMid),
                size: Position3D(x: sSpan, y: thickness, z: zSpan)
            )
        case .yMax:
            return PatchPlacement(
                center: Position3D(x: sMid, y: scene.sizeYM + outward, z: zMid),
                size: Position3D(x: sSpan, y: thickness, z: zSpan)
            )
        }
    }

    /// Rebuild key for RealityView. Counts are not enough: moving a window
    /// or seat must recreate the schematic meshes.
    /// Computation-frame velocity mapped the same way as a position: (x, z, −y).
    public static func displayVelocity(ux: Double, uy: Double, uz: Double) -> DisplayMetres {
        DisplayMetres(x: Float(ux), y: Float(uz), z: Float(-uy))
    }

    /// Arrow shaft length in display metres. Weak office jets (~0.03 m/s) would
    /// be invisible at 1:1, so length is a relative scale, not a displacement.
    public static func glyphDisplayLength(mag: Double, maxMag: Double) -> Float {
        let shortest: Float = 0.12
        let longest: Float = 0.38
        guard maxMag > 0 else { return shortest }
        let t = Float(min(1, max(0, mag / maxMag)))
        return shortest + t * (longest - shortest)
    }

    public static func buildID(scene: RoomScene, fieldHash: String?, paletteKey: String?, flowHash: String? = nil) -> String {
        var parts = ["room:\(format(scene.sizeXM)),\(format(scene.sizeYM)),\(format(scene.sizeZM))"]
        for (index, window) in scene.windows.enumerated() {
            parts.append("w\(index):\(patchKey(window))")
        }
        for (index, door) in scene.doors.enumerated() {
            parts.append("d\(index):\(patchKey(door))")
        }
        if let supply = scene.supply {
            parts.append("sup:\(patchKey(supply))")
        }
        if let returnAir = scene.returnAir {
            parts.append("ret:\(patchKey(returnAir))")
        }
        for box in scene.furniture {
            parts.append(
                "f:\(box.id):\(format(box.origin.x)),\(format(box.origin.y)),\(format(box.origin.z)):\(format(box.size.x)),\(format(box.size.y)),\(format(box.size.z))"
            )
        }
        for seat in scene.seats {
            parts.append("s:\(seat.id):\(format(seat.position.x)),\(format(seat.position.y)),\(format(seat.position.z))")
        }
        parts.append(fieldHash ?? "-")
        parts.append(paletteKey ?? "-")
        parts.append(flowHash ?? "-")
        return parts.joined(separator: "|")
    }

    /// Seat-height plane covering every cell, including the half-spacing
    /// around the first and last centres. Failed quality yields no plane.
    public static func slicePlane(field: FieldSlice) -> SlicePlaneLayout? {
        guard field.quality == "passed", field.shape.nx > 0, field.shape.ny > 0 else {
            return nil
        }
        let countX = Double(field.shape.nx)
        let countY = Double(field.shape.ny)
        return SlicePlaneLayout(
            width: Float(countX * field.spacingM.x),
            depth: Float(countY * field.spacingM.y),
            center: Position3D(
                x: field.originM.x + (countX - 1) * field.spacingM.x / 2,
                y: field.originM.y + (countY - 1) * field.spacingM.y / 2,
                z: field.zM
            )
        )
    }

    private static func patchKey(_ patch: WallPatchScene) -> String {
        "\(patch.wall.rawValue):\(format(patch.s0M)),\(format(patch.s1M)),\(format(patch.z0M)),\(format(patch.z1M))"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.5f", value)
    }
}
