#if os(iOS) || os(tvOS)
import UIKit
#else
import AppKit
#endif
import Foundation
import RealityKit
import SimuCore

#if os(iOS) || os(tvOS)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif

/// Platform colour for UnlitMaterial. Kept local so SimuVisualization does
/// not leak AppKit/UIKit types into the display DTO layer.
@available(macOS 15.0, iOS 18.0, *)
private enum RoomDisplayColor {
    static var wall: PlatformColor { rgba(0.72, 0.76, 0.80, 0.28) }
    static var floor: PlatformColor { rgba(0.52, 0.42, 0.32, 0.95) }

    static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> PlatformColor {
        #if os(iOS) || os(tvOS)
        UIColor(red: r, green: g, blue: b, alpha: a)
        #else
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        #endif
    }

    static func unlit(_ color: PlatformColor, transparent: Bool) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if transparent {
            material.blending = .transparent(opacity: 0.35)
        }
        return material
    }
}

/// Builds the viewer-only room graph. Entity work stays on MainActor because
/// RealityKit Entity is not Sendable under Swift 6.
@available(macOS 15.0, iOS 18.0, *)
@MainActor
enum RoomEntityBuilder {
    static let rootName = "simunow.room"

    static func makeRoot(
        scene: RoomScene,
        field: FieldSlice?,
        palette: SlicePalette?,
        flow: FlowOverlay? = nil
    ) async -> Entity {
        let root = Entity()
        root.name = rootName
        addFloor(to: root, scene: scene)
        addWalls(to: root, scene: scene)
        for window in scene.windows {
            addOpening(window, kind: .window, to: root, scene: scene)
        }
        for door in scene.doors {
            addOpening(door, kind: .door, to: root, scene: scene)
        }
        if let supply = scene.supply {
            addFacingMesh(supply, to: root, scene: scene, make: RoomSchematicMeshes.airConditioner)
        }
        if let returnAir = scene.returnAir {
            addFacingMesh(returnAir, to: root, scene: scene, make: RoomSchematicMeshes.returnGrille)
        }
        for box in scene.furniture {
            addFurniture(box, to: root, scene: scene)
        }
        if let field, let palette, let image = SliceTextureBuilder.cgImage(field: field, palette: palette) {
            await addSlice(image, field: field, to: root, scene: scene)
        }
        if let flow {
            RoomFlowMeshes.addOverlay(flow, to: root, scene: scene)
        }
        for seat in scene.seats {
            addOccupiedSeat(seat, to: root, scene: scene)
        }
        return root
    }

    /// Yaw about display Y, then pitch about display X — the same order as
    /// `IsometricProjection`, so Canvas and RealityKit share one heading.
    static func applyOrbit(_ root: Entity, scene: RoomScene, orbit: ViewportOrbit) {
        let yaw = simd_quatf(angle: Float(orbit.yawRadians), axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: Float(orbit.pitchRadians), axis: SIMD3<Float>(1, 0, 0))
        root.orientation = pitch * yaw
        let scale = orbit.fitScale(sizeXM: scene.sizeXM, sizeYM: scene.sizeYM, sizeZM: scene.sizeZM)
        root.scale = SIMD3<Float>(repeating: scale)
    }

    private static func addFloor(to root: Entity, scene: RoomScene) {
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM / 2, y: scene.sizeYM / 2, z: 0),
            size: Position3D(x: scene.sizeXM, y: scene.sizeYM, z: 0.03),
            scene: scene,
            material: RoomDisplayColor.unlit(RoomDisplayColor.floor, transparent: false)
        )
    }

    private static func addWalls(to root: Entity, scene: RoomScene) {
        let wall = RoomDisplayColor.unlit(RoomDisplayColor.wall, transparent: true)
        let thickness = 0.04
        addBox(
            to: root,
            center: Position3D(x: 0, y: scene.sizeYM / 2, z: scene.sizeZM / 2),
            size: Position3D(x: thickness, y: scene.sizeYM, z: scene.sizeZM),
            scene: scene,
            material: wall
        )
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM, y: scene.sizeYM / 2, z: scene.sizeZM / 2),
            size: Position3D(x: thickness, y: scene.sizeYM, z: scene.sizeZM),
            scene: scene,
            material: wall
        )
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM / 2, y: 0, z: scene.sizeZM / 2),
            size: Position3D(x: scene.sizeXM, y: thickness, z: scene.sizeZM),
            scene: scene,
            material: wall
        )
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM / 2, y: scene.sizeYM, z: scene.sizeZM / 2),
            size: Position3D(x: scene.sizeXM, y: thickness, z: scene.sizeZM),
            scene: scene,
            material: wall
        )
    }

    private static func addOpening(
        _ patch: WallPatchScene,
        kind: RoomSchematicMeshes.OpeningKind,
        to root: Entity,
        scene: RoomScene
    ) {
        let placed = RoomDisplayLayout.patchPlacement(patch, scene: scene, outward: 0.03)
        let extents = RoomDisplayLayout.displayBoxExtents(size: placed.size)
        let display = RoomDisplayLayout.centeredDisplay(placed.center, scene: scene)
        root.addChild(
            RoomSchematicMeshes.opening(
                center: SIMD3(display.x, display.y, display.z),
                size: SIMD3(extents.width, extents.height, extents.depth),
                kind: kind
            )
        )
    }

    private static func addFacingMesh(
        _ patch: WallPatchScene,
        to root: Entity,
        scene: RoomScene,
        make: (SIMD3<Float>, SIMD3<Float>) -> Entity
    ) {
        let placed = RoomDisplayLayout.patchPlacement(patch, scene: scene, outward: 0)
        let display = RoomDisplayLayout.centeredDisplay(placed.center, scene: scene)
        let facing = RoomDisplayLayout.inwardDisplayFacing(patch.wall)
        root.addChild(
            make(
                SIMD3(display.x, display.y, display.z),
                SIMD3(facing.x, facing.y, facing.z)
            )
        )
    }

    private static func addFurniture(_ box: FurnitureScene, to root: Entity, scene: RoomScene) {
        let center = Position3D(
            x: box.origin.x + box.size.x / 2,
            y: box.origin.y + box.size.y / 2,
            z: box.origin.z + box.size.z / 2
        )
        let extents = RoomDisplayLayout.displayBoxExtents(size: box.size)
        let display = RoomDisplayLayout.centeredDisplay(center, scene: scene)
        root.addChild(
            RoomSchematicMeshes.desk(
                center: SIMD3(display.x, display.y, display.z),
                size: SIMD3(extents.width, extents.height, extents.depth)
            )
        )
    }

    private static func addSlice(_ image: CGImage, field: FieldSlice, to root: Entity, scene: RoomScene) async {
        guard let plane = RoomDisplayLayout.slicePlane(field: field) else {
            return
        }
        do {
            let texture = try await TextureResource(
                image: image,
                withName: "simunow.seat-height-slice",
                options: TextureResource.CreateOptions(semantic: .color)
            )
            let entity = ModelEntity(
                mesh: .generatePlane(width: plane.width, depth: plane.depth),
                materials: [UnlitMaterial(texture: texture)]
            )
            let display = RoomDisplayLayout.centeredDisplay(plane.center, scene: scene)
            entity.position = SIMD3(display.x, display.y, display.z)
            root.addChild(entity)
        } catch {
            // Missing texture leaves the room visible; colour is never invented.
            return
        }
    }

    private static func addOccupiedSeat(_ seat: SeatScene, to root: Entity, scene: RoomScene) {
        let display = RoomDisplayLayout.centeredDisplay(RoomDisplayLayout.seatFloor(seat), scene: scene)
        root.addChild(RoomSchematicMeshes.occupiedSeat(atFloor: SIMD3(display.x, display.y, display.z)))
    }

    private static func addBox(
        to root: Entity,
        center: Position3D,
        size: Position3D,
        scene: RoomScene,
        material: UnlitMaterial
    ) {
        let extents = RoomDisplayLayout.displayBoxExtents(size: size)
        let entity = ModelEntity(
            mesh: .generateBox(width: extents.width, height: extents.height, depth: extents.depth),
            materials: [material]
        )
        let display = RoomDisplayLayout.centeredDisplay(center, scene: scene)
        entity.position = SIMD3(display.x, display.y, display.z)
        root.addChild(entity)
    }
}
