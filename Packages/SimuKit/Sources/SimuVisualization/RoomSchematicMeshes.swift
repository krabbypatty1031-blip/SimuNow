#if os(iOS) || os(tvOS)
import UIKit
#else
import AppKit
#endif
import RealityKit
import simd

#if os(iOS) || os(tvOS)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif

/// Hand-built schematic meshes. Sizes are a display convention so a
/// split-AC, window, chair or person can be recognised; they are not
/// measured CAD and they do not change loads, flows or sample points.
@available(macOS 15.0, iOS 18.0, *)
@MainActor
enum RoomSchematicMeshes {
    enum OpeningKind {
        case window
        case door
    }

    static func desk(center: SIMD3<Float>, size: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = center
        let height = size.y
        let topThickness = min(0.04, max(height * 0.08, 0.02))
        // Tall or very thin boxes stay solid so a cabinet is not forced into four legs.
        if height > 1.15 || min(size.x, size.z) < 0.25 {
            root.addChild(box(size, at: .zero, color: woodDark))
            return root
        }
        let topY = height / 2 - topThickness / 2
        root.addChild(box(SIMD3(size.x, topThickness, size.z), at: SIMD3(0, topY, 0), color: woodLight))
        let legHeight = max(height - topThickness, 0.05)
        let legY = -height / 2 + legHeight / 2
        let insetX = min(0.08, size.x * 0.18)
        let insetZ = min(0.08, size.z * 0.18)
        for x in [-1, 1] as [Float] {
            for z in [-1, 1] as [Float] {
                let leg = cylinder(height: legHeight, radius: 0.02, color: woodDark)
                leg.position = SIMD3(x * (size.x / 2 - insetX), legY, z * (size.z / 2 - insetZ))
                root.addChild(leg)
            }
        }
        return root
    }

    /// Chair plus a seated figure. The figure is a mannequin, not a scanned occupant.
    static func occupiedSeat(atFloor floor: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = floor
        root.addChild(box(SIMD3(0.46, 0.04, 0.42), at: SIMD3(0, 0.45, -0.02), color: woodLight))
        root.addChild(box(SIMD3(0.42, 0.38, 0.03), at: SIMD3(0, 0.72, 0.18), color: woodDark))
        for x in [-0.18, 0.18] as [Float] {
            for z in [-0.16, 0.14] as [Float] {
                let leg = cylinder(height: 0.43, radius: 0.016, color: woodDark)
                leg.position = SIMD3(x, 0.215, z)
                root.addChild(leg)
            }
        }
        root.addChild(box(SIMD3(0.34, 0.36, 0.18), at: SIMD3(0, 0.74, -0.04), color: shirt))
        root.addChild(sphere(radius: 0.10, at: SIMD3(0, 1.04, -0.04), color: mannequin))
        return root
    }

    /// Wall unit. Local +Z is `facing`, into the room, so the body hangs off the wall.
    static func airConditioner(at point: SIMD3<Float>, facing: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = point
        root.orientation = orientation(facing: facing)
        let depth: Float = 0.20
        root.addChild(box(SIMD3(0.92, 0.30, depth), at: SIMD3(0, 0, depth / 2), color: unitWhite))
        root.addChild(box(SIMD3(0.72, 0.05, 0.012), at: SIMD3(0, -0.06, depth - 0.004), color: vent))
        root.addChild(box(SIMD3(0.04, 0.02, 0.012), at: SIMD3(0.38, 0.08, depth - 0.004), color: indicator))
        return root
    }

    /// Return grille, distinct from the supply unit so the two terminals stay readable.
    static func returnGrille(at point: SIMD3<Float>, facing: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = point
        root.orientation = orientation(facing: facing)
        let depth: Float = 0.06
        root.addChild(box(SIMD3(0.58, 0.18, depth), at: SIMD3(0, 0, depth / 2), color: grilleTan))
        for offset: Float in [-0.04, 0, 0.04] {
            root.addChild(box(SIMD3(0.48, 0.012, 0.01), at: SIMD3(0, offset, depth), color: vent))
        }
        return root
    }

    static func opening(center: SIMD3<Float>, size: SIMD3<Float>, kind: OpeningKind) -> Entity {
        let root = Entity()
        root.position = center
        let thin = thinAxis(size)
        var depth = size
        depth[thin] = max(size[thin], 0.045)
        let wide = [0, 1, 2].filter { $0 != thin }
        let frame: Float = 0.055
        let spanA = size[wide[0]]
        let spanB = size[wide[1]]
        var bar = depth
        bar[wide[0]] = spanA
        bar[wide[1]] = frame
        var low = SIMD3<Float>.zero
        low[wide[1]] = -spanB / 2 + frame / 2
        var high = SIMD3<Float>.zero
        high[wide[1]] = spanB / 2 - frame / 2
        let frameColor = kind == .window ? frameWhite : woodDark
        root.addChild(box(bar, at: low, color: frameColor))
        root.addChild(box(bar, at: high, color: frameColor))
        var stile = depth
        stile[wide[0]] = frame
        stile[wide[1]] = max(spanB - frame * 2, frame)
        var left = SIMD3<Float>.zero
        left[wide[0]] = -spanA / 2 + frame / 2
        var right = SIMD3<Float>.zero
        right[wide[0]] = spanA / 2 - frame / 2
        root.addChild(box(stile, at: left, color: frameColor))
        root.addChild(box(stile, at: right, color: frameColor))
        var fill = depth
        fill[thin] = depth[thin] * 0.45
        fill[wide[0]] = max(spanA - frame * 2, 0.02)
        fill[wide[1]] = max(spanB - frame * 2, 0.02)
        if kind == .window {
            root.addChild(box(fill, at: .zero, color: glassTint, opacity: 0.38))
        } else {
            root.addChild(box(fill, at: .zero, color: woodLight))
            var handle = SIMD3<Float>(repeating: 0.03)
            handle[thin] = 0.04
            var handleAt = SIMD3<Float>.zero
            handleAt[wide[0]] = spanA * 0.28
            handleAt[thin] = depth[thin] * 0.35
            root.addChild(box(handle, at: handleAt, color: bezel))
        }
        return root
    }

    // MARK: - Parts

    private static func orientation(facing: SIMD3<Float>) -> simd_quatf {
        let direction = simd_length(facing) > 0.001 ? simd_normalize(facing) : SIMD3<Float>(0, 0, 1)
        return simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)
    }

    private static func box(
        _ size: SIMD3<Float>,
        at position: SIMD3<Float>,
        color: PlatformColor,
        opacity: Float? = nil
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [unlit(color, opacity: opacity)])
        entity.position = position
        return entity
    }

    private static func cylinder(height: Float, radius: Float, color: PlatformColor) -> ModelEntity {
        ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [unlit(color)])
    }

    private static func sphere(radius: Float, at position: SIMD3<Float>, color: PlatformColor) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: radius), materials: [unlit(color)])
        entity.position = position
        return entity
    }

    private static func unlit(_ color: PlatformColor, opacity: Float? = nil) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if let opacity {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    private static func thinAxis(_ size: SIMD3<Float>) -> Int {
        if size.x <= size.y && size.x <= size.z { return 0 }
        if size.y <= size.z { return 1 }
        return 2
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> PlatformColor {
        #if os(iOS) || os(tvOS)
        UIColor(red: r, green: g, blue: b, alpha: a)
        #else
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        #endif
    }

    private static var woodLight: PlatformColor { rgba(0.72, 0.55, 0.36) }
    private static var woodDark: PlatformColor { rgba(0.45, 0.30, 0.18) }
    private static var shirt: PlatformColor { rgba(0.25, 0.42, 0.62) }
    private static var mannequin: PlatformColor { rgba(0.78, 0.73, 0.66) }
    private static var bezel: PlatformColor { rgba(0.16, 0.16, 0.16) }
    private static var unitWhite: PlatformColor { rgba(0.93, 0.93, 0.93) }
    private static var vent: PlatformColor { rgba(0.25, 0.25, 0.25) }
    private static var indicator: PlatformColor { rgba(0.35, 0.75, 0.85) }
    private static var grilleTan: PlatformColor { rgba(0.86, 0.62, 0.38) }
    private static var frameWhite: PlatformColor { rgba(0.95, 0.95, 0.95) }
    private static var glassTint: PlatformColor { rgba(0.55, 0.82, 0.90) }
}
