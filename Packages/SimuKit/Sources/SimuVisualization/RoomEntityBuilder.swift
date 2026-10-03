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

#if os(iOS) || os(tvOS)
private typealias PlatformFont = UIFont
#else
private typealias PlatformFont = NSFont
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
        flow: FlowOverlay? = nil,
        seatSamples: [SeatSample]? = nil,
        copy: UserFacingCopy = .english
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
            RoomFlowMeshes.addOverlay(flow, to: root, scene: scene, copy: copy)
        }
        for seat in scene.seats {
            addOccupiedSeat(seat, to: root, scene: scene)
            // Per-seat air temperature label from the quality-passed L2
            // result; seats without a sample keep only the mannequin.
            if let sample = seatSamples?.first(where: { $0.id == seat.id }) {
                addSeatLabel(sample, seat: seat, to: root, scene: scene)
            }
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
            material: RoomDisplayColor.unlit(RoomDisplayColor.floor, transparent: false),
            name: PlacementGeometry.floorEntityName
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
            material: wall,
            name: PlacementGeometry.wallEntityName(.xMin)
        )
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM, y: scene.sizeYM / 2, z: scene.sizeZM / 2),
            size: Position3D(x: thickness, y: scene.sizeYM, z: scene.sizeZM),
            scene: scene,
            material: wall,
            name: PlacementGeometry.wallEntityName(.xMax)
        )
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM / 2, y: 0, z: scene.sizeZM / 2),
            size: Position3D(x: scene.sizeXM, y: thickness, z: scene.sizeZM),
            scene: scene,
            material: wall,
            name: PlacementGeometry.wallEntityName(.yMin)
        )
        addBox(
            to: root,
            center: Position3D(x: scene.sizeXM / 2, y: scene.sizeYM, z: scene.sizeZM / 2),
            size: Position3D(x: scene.sizeXM, y: thickness, z: scene.sizeZM),
            scene: scene,
            material: wall,
            name: PlacementGeometry.wallEntityName(.yMax)
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
            RoomSchematicMeshes.furniture(
                kind: box.kind,
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

    /// Per-seat L2 air-temperature label, laid flat above the seated person
    /// so the default overhead orbit reads it like a floor plan. Generated at
    /// a regular 100 pt font size and scaled down, because tiny CoreText
    /// font sizes can degrade path quality; the scale lands roughly 12 cm of
    /// text height. A white backing board keeps black digits readable over
    /// both the deep-blue cold end and the bright warm end of the slice.
    private static func addSeatLabel(_ sample: SeatSample, seat: SeatScene, to root: Entity, scene: RoomScene) {
        let text = RoomDisplayLayout.seatLabelText(seat: seat, sample: sample)
        guard let font = platformLabelFont() else { return }
        let mesh: MeshResource
        do {
            mesh = try MeshResource.generateText(
                text,
                extrusionDepth: SeatLabelStyle.extrusionPt,
                font: font
            )
        } catch {
            // A failed text mesh leaves the room and mannequin untouched.
            return
        }
        let scale = SeatLabelStyle.worldScale
        // Text bounds in metres (font units scaled down), used to centre the board.
        let textM = mesh.bounds.extents * scale
        // Clamp above the seated person and below the ceiling.
        let labelZM = min(SeatLabelStyle.heightM, max(0.6, scene.sizeZM - 0.15))
        let anchor = Entity()
        anchor.name = "simunow.seat-label.\(seat.id)"
        let display = RoomDisplayLayout.centeredDisplay(
            Position3D(x: seat.position.x, y: seat.position.y, z: labelZM),
            scene: scene
        )
        anchor.position = SIMD3(display.x, display.y, display.z)
        // Lay flat: rotate the text face from local +Z to up (+Y); the text
        // top then points to -Z (the room's far side), the floor-plan reading
        // direction for the default overhead orbit.
        anchor.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

        let textEntity = ModelEntity(
            mesh: mesh,
            materials: [RoomDisplayColor.unlit(.black, transparent: false)]
        )
        textEntity.scale = SIMD3(repeating: scale)
        anchor.addChild(textEntity)

        // generatePlane(width:height:) faces +Z like the text, so the same
        // anchor rotation lays the board flat; it sits just behind the text
        // face to avoid z-fighting.
        let boardEntity = ModelEntity(
            mesh: .generatePlane(
                width: textM.x + SeatLabelStyle.boardPaddingM,
                height: textM.y + SeatLabelStyle.boardPaddingM * 0.6
            ),
            materials: [SeatLabelStyle.boardMaterial]
        )
        boardEntity.position = SIMD3(textM.x / 2, textM.y / 2, -SeatLabelStyle.boardOffsetM)
        anchor.addChild(boardEntity)

        root.addChild(anchor)
    }

    /// Seat label typography and board style, all in display metres.
    private enum SeatLabelStyle {
        /// CoreText renders a regular font size; the entity scales it down.
        static let fontPt: CGFloat = 100
        /// 100 pt units to metres, landing ~12 cm of text height.
        static let worldScale: Float = 0.0011
        /// Text extrusion in font units; after scaling it is ~2 mm thick.
        static let extrusionPt: Float = 2
        /// Label plane height above the floor: over the seated person's
        /// head, under the ceiling, and clear of the seat-height slice.
        static let heightM: Double = 1.45
        /// White board padding around the text bounds, metres.
        static let boardPaddingM: Float = 0.10
        /// Board sits this far behind the text face, metres.
        static let boardOffsetM: Float = 0.004
        /// Near-opaque white board: readable over cold-blue and warm-red ends.
        static var boardMaterial: UnlitMaterial {
            var material = UnlitMaterial(color: PlatformColor.white)
            material.blending = .transparent(opacity: 0.85)
            return material
        }
    }

    /// Platform font for text meshes without leaking AppKit/UIKit types.
    private static func platformLabelFont() -> PlatformFont? {
        PlatformFont.systemFont(ofSize: SeatLabelStyle.fontPt, weight: .semibold)
    }

    private static func addBox(
        to root: Entity,
        center: Position3D,
        size: Position3D,
        scene: RoomScene,
        material: UnlitMaterial,
        name: String? = nil
    ) {
        let extents = RoomDisplayLayout.displayBoxExtents(size: size)
        let entity = ModelEntity(
            mesh: .generateBox(width: extents.width, height: extents.height, depth: extents.depth),
            materials: [material]
        )
        // A named collision box lets viewport taps hit-test this face
        // (PlacementGeometry resolves the name into a draft surface).
        if let name {
            entity.name = name
            entity.collision = CollisionComponent(
                shapes: [.generateBox(width: extents.width, height: extents.height, depth: extents.depth)]
            )
        }
        let display = RoomDisplayLayout.centeredDisplay(center, scene: scene)
        entity.position = SIMD3(display.x, display.y, display.z)
        root.addChild(entity)
    }
}
