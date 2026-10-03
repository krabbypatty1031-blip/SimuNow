#if os(iOS) || os(tvOS)
import UIKit
#else
import AppKit
#endif
import RealityKit
import SimuCore
import simd

#if os(iOS) || os(tvOS)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif

/// Steady-field glyphs, streamlines, and looping beads. Length and lap
/// time are display scales; the overlay is not a cool-down animation.
@available(macOS 15.0, iOS 18.0, *)
@MainActor
enum RoomFlowMeshes {
    static let groupName = "simunow.flow"

    static func addOverlay(_ flow: FlowOverlay, to root: Entity, scene: RoomScene) {
        guard flow.quality == "passed" else { return }
        let maxMag = flow.stats.maxMag ?? flow.glyphs.map(\.mag).max() ?? 0
        let group = Entity()
        group.name = groupName
        // 「送风」/「回风」 name where the mesh actually injects and
        // extracts air — the full-span band at the terminal height, not
        // the schematic AC box.
        if let supply = scene.supply {
            group.addChild(terminalLabel(supply, scene: scene, text: "送风", color: rgba(0.45, 0.82, 1.0)))
        }
        if let returnAir = scene.returnAir {
            group.addChild(terminalLabel(returnAir, scene: scene, text: "回风", color: rgba(1.0, 0.72, 0.32)))
        }
        for glyph in flow.glyphs {
            group.addChild(arrow(glyph, maxMag: maxMag, scene: scene))
        }
        for line in flow.lines {
            addStreamline(line, maxMag: maxMag, to: group, scene: scene)
        }
        addBeads(flow, to: group, scene: scene, phase: 0)
        root.addChild(group)
    }

    /// Move existing beads. Must not recreate the room graph or the field.
    static func updateBeads(_ flow: FlowOverlay, in root: Entity, scene: RoomScene, phase: Double) {
        guard flow.quality == "passed", let group = root.findEntity(named: groupName) else {
            return
        }
        var beadIndex = 0
        for line in flow.lines {
            let points = line.points.map(\.position)
            for bead in 0..<RoomDisplayLayout.flowParticleBeadCount {
                guard let entity = group.findEntity(named: beadName(beadIndex)),
                      let sample = RoomDisplayLayout.polylineSample(
                        points: points,
                        phase: RoomDisplayLayout.flowBeadPhase(
                            clock: phase,
                            index: bead,
                            count: RoomDisplayLayout.flowParticleBeadCount
                        )
                      ) else {
                    beadIndex += 1
                    continue
                }
                let display = RoomDisplayLayout.centeredDisplay(sample, scene: scene)
                entity.position = SIMD3(display.x, display.y, display.z)
                beadIndex += 1
            }
        }
    }

    private static func arrow(_ glyph: FlowOverlay.Glyph, maxMag: Double, scene: RoomScene) -> Entity {
        let direction = RoomDisplayLayout.displayVelocity(ux: glyph.ux, uy: glyph.uy, uz: glyph.uz)
        let vector = SIMD3<Float>(direction.x, direction.y, direction.z)
        let length = RoomDisplayLayout.glyphDisplayLength(mag: glyph.mag, maxMag: maxMag)
        let color = speedColor(mag: glyph.mag, maxMag: maxMag)
        let root = Entity()
        let display = RoomDisplayLayout.centeredDisplay(glyph.position, scene: scene)
        root.position = SIMD3(display.x, display.y, display.z)
        if simd_length(vector) > 1e-5 {
            root.orientation = lookRotation(from: SIMD3(0, 1, 0), to: simd_normalize(vector))
        }
        let shaft = ModelEntity(
            mesh: .generateCylinder(height: length * 0.78, radius: 0.012),
            materials: [unlit(color)]
        )
        shaft.position = SIMD3(0, length * 0.39, 0)
        root.addChild(shaft)
        let head = ModelEntity(
            mesh: .generateCone(height: length * 0.22, radius: 0.028),
            materials: [unlit(color)]
        )
        head.position = SIMD3(0, length * 0.89, 0)
        root.addChild(head)
        return root
    }

    private static func addStreamline(
        _ line: FlowOverlay.Streamline,
        maxMag: Double,
        to root: Entity,
        scene: RoomScene
    ) {
        let points = line.points
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let a = RoomDisplayLayout.centeredDisplay(points[index].position, scene: scene)
            let b = RoomDisplayLayout.centeredDisplay(points[index + 1].position, scene: scene)
            let start = SIMD3<Float>(a.x, a.y, a.z)
            let end = SIMD3<Float>(b.x, b.y, b.z)
            let delta = end - start
            let length = simd_length(delta)
            guard length > 0.02 else { continue }
            let segment = ModelEntity(
                mesh: .generateCylinder(height: length, radius: 0.010),
                materials: [unlit(speedColor(mag: points[index].mag, maxMag: maxMag))]
            )
            segment.position = (start + end) / 2
            segment.orientation = lookRotation(from: SIMD3(0, 1, 0), to: delta / length)
            root.addChild(segment)
        }
    }

    private static func addBeads(
        _ flow: FlowOverlay,
        to root: Entity,
        scene: RoomScene,
        phase: Double
    ) {
        var beadIndex = 0
        for line in flow.lines {
            let points = line.points.map(\.position)
            for bead in 0..<RoomDisplayLayout.flowParticleBeadCount {
                let entity = ModelEntity(
                    mesh: .generateSphere(radius: 0.038),
                    materials: [unlit(beadColor)]
                )
                entity.name = beadName(beadIndex)
                if let sample = RoomDisplayLayout.polylineSample(
                    points: points,
                    phase: RoomDisplayLayout.flowBeadPhase(
                        clock: phase,
                        index: bead,
                        count: RoomDisplayLayout.flowParticleBeadCount
                    )
                ) {
                    let display = RoomDisplayLayout.centeredDisplay(sample, scene: scene)
                    entity.position = SIMD3(display.x, display.y, display.z)
                }
                root.addChild(entity)
                beadIndex += 1
            }
        }
    }

    private static func beadName(_ index: Int) -> String {
        "simunow.flow.bead.\(index)"
    }

    /// 「送风」/「回风」 beside and above the schematic device, facing into
    /// the room. A dark plate sits behind the glyphs so they stay readable
    /// against the white AC body or the heatmap.
    private static func terminalLabel(
        _ patch: WallPatchScene,
        scene: RoomScene,
        text: String,
        color: PlatformColor
    ) -> Entity {
        let anchor = RoomDisplayLayout.terminalLabelAnchor(patch, scene: scene)
        let display = RoomDisplayLayout.centeredDisplay(anchor, scene: scene)
        let container = Entity()
        container.name = "simunow.flow.label." + (text == "送风" ? "supply" : "return")
        container.position = SIMD3(display.x, display.y, display.z)
        container.orientation = labelFacing(patch.wall)
        if let mesh = textMesh(text) {
            let extents = mesh.bounds.extents
            let plate = ModelEntity(
                mesh: .generateBox(
                    width: extents.x + 0.10,
                    height: extents.y + 0.06,
                    depth: 0.012
                ),
                materials: [unlit(rgba(0.08, 0.09, 0.11))]
            )
            plate.position = SIMD3(0, 0, -0.012)
            container.addChild(plate)
            let glyph = ModelEntity(mesh: mesh, materials: [unlit(color)])
            // generateText anchors lower-left; re-centre on the plate.
            glyph.position = -mesh.bounds.center
            container.addChild(glyph)
        }
        return container
    }

    /// RealityKit treats the font size as metres. 0.38 m is readable next
    /// to the 0.92 m AC body without filling the room.
    private static func textMesh(_ text: String) -> MeshResource? {
        #if os(iOS) || os(tvOS)
        let font = UIFont.boldSystemFont(ofSize: 0.38)
        #else
        let font = NSFont.boldSystemFont(ofSize: 0.38)
        #endif
        return MeshResource.generateText(text, extrusionDepth: 0.016, font: font)
    }

    /// Yaw per wall so the text faces into the room and reads left-to-right
    /// from inside, in display space (computation +X stays display +X).
    private static func labelFacing(_ wall: WallFace) -> simd_quatf {
        switch wall {
        case .xMin:
            return simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        case .xMax:
            return simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0))
        case .yMin:
            return simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        case .yMax:
            return simd_quatf()
        }
    }

    private static func lookRotation(from axis: SIMD3<Float>, to direction: SIMD3<Float>) -> simd_quatf {
        let a = simd_normalize(axis)
        let b = simd_normalize(direction)
        let cosine = simd_dot(a, b)
        if cosine > 0.9999 {
            return simd_quatf()
        }
        if cosine < -0.9999 {
            let other = abs(a.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
            return simd_quatf(angle: .pi, axis: simd_normalize(simd_cross(a, other)))
        }
        return simd_quatf(from: a, to: b)
    }

    private static func speedColor(mag: Double, maxMag: Double) -> PlatformColor {
        let t = CGFloat(maxMag > 0 ? min(1, max(0, mag / maxMag)) : 0)
        return rgba(0.20 + 0.35 * t, 0.55 + 0.35 * t, 0.70 + 0.22 * t)
    }

    /// Bright enough to read as motion against the dimmer streamline tubes.
    private static var beadColor: PlatformColor {
        rgba(0.72, 0.96, 1.0)
    }

    private static func unlit(_ color: PlatformColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> PlatformColor {
        #if os(iOS) || os(tvOS)
        UIColor(red: r, green: g, blue: b, alpha: 1)
        #else
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        #endif
    }
}
