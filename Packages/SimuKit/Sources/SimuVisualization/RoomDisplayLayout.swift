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

    /// The band the solver actually breathes through: the terminal's
    /// z-range stretched over the whole wall span. `write_openfoam_room`
    /// can only make full-wall bands and scales velocity/flux to preserve
    /// the project's m3/s and W. The schematic terminal marks the device;
    /// this band is where the mesh lets air in or out.
    public static func solvedBandPatch(_ patch: WallPatchScene, scene: RoomScene) -> WallPatchScene {
        let span: Double
        switch patch.wall {
        case .xMin, .xMax:
            span = scene.sizeYM
        case .yMin, .yMax:
            span = scene.sizeXM
        }
        return WallPatchScene(
            wall: patch.wall,
            s0M: 0,
            s1M: span,
            z0M: patch.z0M,
            z1M: patch.z1M
        )
    }

    /// Where 「送风」/「回风」 sit: beside and above the schematic device,
    /// and far enough into the room that the 0.20 m AC body cannot swallow
    /// the glyphs. Uses the visible terminal, not the full-wall solved band.
    public static let terminalLabelInwardM = 0.42
    public static let terminalLabelAlongM = 0.36
    public static let terminalLabelAboveM = 0.20

    public static func terminalLabelAnchor(_ patch: WallPatchScene, scene: RoomScene) -> Position3D {
        let wallSpan: Double
        switch patch.wall {
        case .xMin, .xMax:
            wallSpan = scene.sizeYM
        case .yMin, .yMax:
            wallSpan = scene.sizeXM
        }
        // Prefer the +s side of the box; flip if that would leave the room.
        let along: Double
        if patch.s1M + Self.terminalLabelAlongM <= wallSpan - 0.10 {
            along = patch.s1M + Self.terminalLabelAlongM
        } else {
            along = max(0.10, patch.s0M - Self.terminalLabelAlongM)
        }
        let above = patch.z1M + Self.terminalLabelAboveM
        let inward = Self.terminalLabelInwardM
        switch patch.wall {
        case .xMin:
            return Position3D(x: inward, y: along, z: above)
        case .xMax:
            return Position3D(x: scene.sizeXM - inward, y: along, z: above)
        case .yMin:
            return Position3D(x: along, y: inward, z: above)
        case .yMax:
            return Position3D(x: along, y: scene.sizeYM - inward, z: above)
        }
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

    /// Display seconds for one bead lap. Not a physical transit time and
    /// not a cool-down clock — office jets would take minutes at 1:1.
    public static let flowParticleLoopSeconds: Double = 3.6
    /// Beads per quality-passed streamline. Density is display-only.
    public static let flowParticleBeadCount = 4

    /// Fractional progress in `[0, 1)` for the schematic loop at `date`.
    public static func flowParticlePhase(at date: Date, period: Double = flowParticleLoopSeconds) -> Double {
        guard period > 0 else { return 0 }
        let wrapped = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let phase = wrapped < 0 ? wrapped + period : wrapped
        return phase / period
    }

    /// Evenly staggered phases so several beads share one loop.
    public static func flowBeadPhase(clock: Double, index: Int, count: Int) -> Double {
        guard count > 0 else { return wrappedUnit(clock) }
        return wrappedUnit(clock + Double(index) / Double(count))
    }

    /// Arc-length sample on a computation-frame polyline. `phase` wraps.
    public static func polylineSample(points: [Position3D], phase: Double) -> Position3D? {
        guard points.count >= 2 else { return nil }
        var cumulative: [Double] = [0]
        var total = 0.0
        for index in 1..<points.count {
            let dx = points[index].x - points[index - 1].x
            let dy = points[index].y - points[index - 1].y
            let dz = points[index].z - points[index - 1].z
            total += (dx * dx + dy * dy + dz * dz).squareRoot()
            cumulative.append(total)
        }
        guard total > 1e-9 else { return points[0] }
        let target = wrappedUnit(phase) * total
        for index in 1..<cumulative.count {
            if target <= cumulative[index] || index == cumulative.count - 1 {
                let span = cumulative[index] - cumulative[index - 1]
                let t = span > 1e-12 ? (target - cumulative[index - 1]) / span : 0
                let start = points[index - 1]
                let end = points[index]
                return Position3D(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t,
                    z: start.z + (end.z - start.z) * t
                )
            }
        }
        return points.last
    }

    private static func wrappedUnit(_ value: Double) -> Double {
        var unit = value.truncatingRemainder(dividingBy: 1)
        if unit < 0 {
            unit += 1
        }
        return unit
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
