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

/// Steady-field glyphs and streamlines. Length is a display scale; the
/// overlay is not a cool-down animation.
@available(macOS 15.0, iOS 18.0, *)
@MainActor
enum RoomFlowMeshes {
    static func addOverlay(_ flow: FlowOverlay, to root: Entity, scene: RoomScene) {
        guard flow.quality == "passed" else { return }
        let maxMag = flow.stats.maxMag ?? flow.glyphs.map(\.mag).max() ?? 0
        let group = Entity()
        group.name = "simunow.flow"
        for glyph in flow.glyphs {
            group.addChild(arrow(glyph, maxMag: maxMag, scene: scene))
        }
        for line in flow.lines {
            addStreamline(line, maxMag: maxMag, to: group, scene: scene)
        }
        root.addChild(group)
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
