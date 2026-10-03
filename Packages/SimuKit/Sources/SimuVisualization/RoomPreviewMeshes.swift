#if os(macOS)
import AppKit
import RealityKit
import simd

/// Hand-built schematic meshes for the read-only preview.
/// Sizes are display conventions. They do not change loads, flows, or sample points.
@available(macOS 15.0, *)
@MainActor
enum RoomPreviewMeshes {
    static func desk(center: SIMD3<Float>, size: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = center
        let height = size.y
        let topThickness = min(0.04, max(height * 0.08, 0.02))
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

    static func chair(at floor: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = floor
        let seatY: Float = 0.45
        root.addChild(box(SIMD3(0.46, 0.04, 0.42), at: SIMD3(0, seatY, -0.02), color: woodLight))
        root.addChild(box(SIMD3(0.42, 0.38, 0.03), at: SIMD3(0, 0.72, 0.18), color: woodDark))
        for x in [-0.18, 0.18] as [Float] {
            for z in [-0.16, 0.14] as [Float] {
                let leg = cylinder(height: 0.43, radius: 0.016, color: woodDark)
                leg.position = SIMD3(x, 0.215, z)
                root.addChild(leg)
            }
        }
        return root
    }

    /// Seated schematic figure facing domain +Y (Apple −Z), toward the template's far wall.
    static func person(at floor: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = floor
        root.addChild(box(SIMD3(0.34, 0.36, 0.18), at: SIMD3(0, 0.74, -0.04), color: shirt))
        root.addChild(sphere(radius: 0.10, at: SIMD3(0, 1.04, -0.04), color: mannequin))
        return root
    }

    static func monitor(at base: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = base
        root.addChild(box(SIMD3(0.16, 0.02, 0.12), at: SIMD3(0, 0.01, 0), color: bezel))
        let neck = cylinder(height: 0.08, radius: 0.012, color: bezel)
        neck.position = SIMD3(0, 0.06, 0)
        root.addChild(neck)
        root.addChild(box(SIMD3(0.48, 0.30, 0.025), at: SIMD3(0, 0.24, 0), color: bezel))
        root.addChild(box(SIMD3(0.42, 0.24, 0.01), at: SIMD3(0, 0.24, 0.012), color: screen))
        return root
    }

    /// Wall unit. Local +Z points along `facing` (the supply direction) into the room.
    static func airConditioner(at point: SIMD3<Float>, facing: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = point
        let direction = simd_length(facing) > 0.001 ? simd_normalize(facing) : SIMD3<Float>(0, 0, 1)
        root.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction)
        let depth: Float = 0.20
        let body = box(SIMD3(0.92, 0.30, depth), at: SIMD3(0, 0, depth / 2), color: unitWhite)
        root.addChild(body)
        root.addChild(box(SIMD3(0.72, 0.05, 0.012), at: SIMD3(0, -0.06, depth - 0.004), color: vent))
        root.addChild(box(SIMD3(0.04, 0.02, 0.012), at: SIMD3(0.38, 0.08, depth - 0.004), color: indicator))
        return root
    }

    static func opening(center: SIMD3<Float>, size: SIMD3<Float>, kind: Kind) -> Entity {
        let root = Entity()
        root.position = center
        let thin = thinAxis(size)
        var depth = size
        depth[thin] = max(size[thin], 0.045)
        let wide = [0, 1, 2].filter { $0 != thin }
        let frame: Float = 0.055
        let spanA = size[wide[0]]
        let spanB = size[wide[1]]
        func place(_ span: SIMD3<Float>, at local: SIMD3<Float>, color: NSColor, opacity: Float? = nil) {
            root.addChild(box(span, at: local, color: color, opacity: opacity))
        }
        var bar = depth
        bar[wide[0]] = spanA
        bar[wide[1]] = frame
        var low = SIMD3<Float>.zero
        low[wide[1]] = -spanB / 2 + frame / 2
        var high = SIMD3<Float>.zero
        high[wide[1]] = spanB / 2 - frame / 2
        let frameColor = kind == .window ? frameWhite : woodDark
        place(bar, at: low, color: frameColor)
        place(bar, at: high, color: frameColor)
        var stile = depth
        stile[wide[0]] = frame
        stile[wide[1]] = max(spanB - frame * 2, frame)
        var left = SIMD3<Float>.zero
        left[wide[0]] = -spanA / 2 + frame / 2
        var right = SIMD3<Float>.zero
        right[wide[0]] = spanA / 2 - frame / 2
        place(stile, at: left, color: frameColor)
        place(stile, at: right, color: frameColor)
        var fill = depth
        fill[thin] = depth[thin] * 0.45
        fill[wide[0]] = max(spanA - frame * 2, 0.02)
        fill[wide[1]] = max(spanB - frame * 2, 0.02)
        if kind == .window {
            place(fill, at: .zero, color: glassTint, opacity: 0.38)
        } else {
            place(fill, at: .zero, color: woodLight)
            var handle = SIMD3<Float>(repeating: 0.03)
            handle[thin] = 0.04
            var handleAt = SIMD3<Float>.zero
            handleAt[wide[0]] = spanA * 0.28
            handleAt[thin] = depth[thin] * 0.35
            place(handle, at: handleAt, color: bezel)
        }
        return root
    }

    static func sample(at center: SIMD3<Float>) -> Entity {
        sphere(radius: 0.028, at: center, color: sampleColor)
    }

    enum Kind { case window, door }

    // MARK: - Parts

    private static func box(_ size: SIMD3<Float>, at position: SIMD3<Float>, color: NSColor, opacity: Float? = nil) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material(color, opacity: opacity)])
        entity.position = position
        return entity
    }

    private static func cylinder(height: Float, radius: Float, color: NSColor) -> ModelEntity {
        ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material(color)])
    }

    private static func sphere(radius: Float, at position: SIMD3<Float>, color: NSColor) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material(color)])
        entity.position = position
        return entity
    }

    private static func material(_ color: NSColor, opacity: Float? = nil) -> RealityKit.Material {
        if let opacity {
            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: color.withAlphaComponent(CGFloat(opacity)))
            glass.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return glass
        }
        return SimpleMaterial(color: color, isMetallic: false)
    }

    private static func thinAxis(_ size: SIMD3<Float>) -> Int {
        if size.x <= size.y && size.x <= size.z { return 0 }
        if size.y <= size.z { return 1 }
        return 2
    }

    private static let woodLight = NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.36, alpha: 1)
    private static let woodDark = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.18, alpha: 1)
    private static let shirt = NSColor(calibratedRed: 0.25, green: 0.42, blue: 0.62, alpha: 1)
    private static let mannequin = NSColor(calibratedRed: 0.78, green: 0.73, blue: 0.66, alpha: 1)
    private static let bezel = NSColor(calibratedWhite: 0.16, alpha: 1)
    private static let screen = NSColor(calibratedRed: 0.75, green: 0.84, blue: 0.88, alpha: 1)
    private static let unitWhite = NSColor(calibratedWhite: 0.93, alpha: 1)
    private static let vent = NSColor(calibratedWhite: 0.25, alpha: 1)
    private static let indicator = NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.85, alpha: 1)
    private static let frameWhite = NSColor(calibratedWhite: 0.95, alpha: 1)
    private static let glassTint = NSColor(calibratedRed: 0.55, green: 0.82, blue: 0.90, alpha: 1)
    private static let sampleColor = NSColor.systemTeal
}
#endif
