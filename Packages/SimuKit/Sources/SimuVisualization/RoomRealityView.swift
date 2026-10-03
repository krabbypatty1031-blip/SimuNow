import RealityKit
import SwiftUI
import SimuCore

/// Viewer-only RealityKit room: orbit, schematic AC / openings / desks /
/// seated people, a quality-gated seat-height slice, and optional steady
/// flow arrows with looping beads. Add/delete in the inspector rebuilds
/// this view. There is no click-to-select and no 3D drag handle — those
/// belong to later schemes.
@available(macOS 15.0, iOS 18.0, *)
public struct RoomRealityView: View {
    private let scene: RoomScene
    private let field: FieldSlice?
    private let flow: FlowOverlay?
    private let sharedPalette: SlicePalette?
    /// Quality-passed L2 seat samples for per-seat temperature labels; nil
    /// or unmatched ids keep the plain seat name, never a fabricated number.
    private let seatSamples: [SeatSample]?
    private let externalYaw: Binding<Double>?
    /// Tap placement (2026-10-04): when a placement mode is armed the next
    /// tap hit-tests the named wall/floor collision boxes and reports the
    /// draft surface it landed on. Camera orbit keeps working; a tap that
    /// misses every named box is ignored, never clamped onto a wall.
    private let isPlacing: Bool
    private let onTapSurface: ((PlacementGeometry.Surface) -> Void)?
    @State private var internalYaw: Double = ViewportOrbit.defaultYaw
    @State private var orbit = ViewportOrbit()
    @State private var dragStart: (yaw: Double, pitch: Double)?
    @State private var pinchStart: Double?
    /// Camera content captured in RealityView's make closure so a later tap
    /// can call `hitTest(point:in:)`. The struct holds the scene's backing
    /// handle, so the copy still resolves the same content.
    @State private var realityContent: RealityViewCameraContent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        scene: RoomScene,
        field: FieldSlice? = nil,
        flow: FlowOverlay? = nil,
        sharedPalette: SlicePalette? = nil,
        yaw: Binding<Double>? = nil,
        seatSamples: [SeatSample]? = nil,
        isPlacing: Bool = false,
        onTapSurface: ((PlacementGeometry.Surface) -> Void)? = nil
    ) {
        self.scene = scene
        self.field = field
        self.flow = flow
        self.sharedPalette = sharedPalette
        self.seatSamples = seatSamples
        self.externalYaw = yaw
        self.isPlacing = isPlacing
        self.onTapSurface = onTapSurface
    }

    private var yaw: Binding<Double> {
        externalYaw ?? $internalYaw
    }

    private var palette: SlicePalette? {
        SlicePalette.resolved(field: field, shared: sharedPalette)
    }

    /// Rebuild geometry only when the draft or field changes. Drag updates
    /// the root transform in `update` and must not recreate meshes. Seat
    /// temperatures are part of the key: a new run must rebuild the labels.
    private var buildID: String {
        RoomDisplayLayout.buildID(
            scene: scene,
            fieldHash: field?.inputHash,
            paletteKey: palette.map { "\($0.minC):\($0.maxC)" },
            flowHash: flow?.inputHash,
            seatKey: seatSamples.map { samples in
                samples
                    .map { "\($0.id):\($0.tC)" }
                    .sorted()
                    .joined(separator: ",")
            }
        )
    }

    public var body: some View {
        // Beads loop on a display clock. Reduce Motion keeps the static path.
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animatesFlow)) { timeline in
            realityContent(phase: RoomDisplayLayout.flowParticlePhase(at: timeline.date))
        }
    }

    private var animatesFlow: Bool {
        !reduceMotion && flow?.quality == "passed" && !(flow?.lines.isEmpty ?? true)
    }

    private func realityContent(phase: Double) -> some View {
        RealityView { content in
            content.camera = .virtual
            // Keep the camera content so a placement tap can hitTest through
            // it later (the make closure's `content` is inout and escapes).
            realityContent = content
            let root = await RoomEntityBuilder.makeRoot(
                scene: scene,
                field: field,
                palette: palette,
                flow: flow,
                seatSamples: seatSamples
            )
            RoomEntityBuilder.applyOrbit(root, scene: scene, orbit: orbit)
            content.add(root)
            content.cameraTarget = root
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == RoomEntityBuilder.rootName }) else {
                return
            }
            RoomEntityBuilder.applyOrbit(root, scene: scene, orbit: orbit)
            if let flow {
                RoomFlowMeshes.updateBeads(flow, in: root, scene: scene, phase: phase)
            }
        }
        .id(buildID)
        .gesture(
            // Placement taps only fire when a mode is armed; orbit drags
            // keep working at all times. A tap without a mode does nothing,
            // so the two interactions never fight.
            SpatialTapGesture()
                .onEnded { value in
                    guard isPlacing, onTapSurface != nil else { return }
                    handlePlacementTap(at: value.location)
                }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? (orbit.yawRadians, orbit.pitchRadians)
                    dragStart = start
                    orbit.applyDrag(translation: value.translation, startYaw: start.0, startPitch: start.1)
                    yaw.wrappedValue = orbit.yawRadians
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let start = pinchStart ?? orbit.distance
                    pinchStart = start
                    orbit.applyMagnification(Double(value), startDistance: start)
                }
                .onEnded { _ in pinchStart = nil }
        )
        .onAppear {
            orbit.yawRadians = yaw.wrappedValue
        }
        .onChange(of: yaw.wrappedValue) { _, newValue in
            if abs(orbit.yawRadians - newValue) > 1e-9 {
                orbit.yawRadians = newValue
            }
        }
        // Removed the top-leading seat-name strip (user request 2026-10-03):
        // per-seat labels in the scene carry the information now.
        .overlay(alignment: .bottom) {
            if palette != nil || flow != nil {
                ViewportLegend(palette: palette, flow: flow)
                    .padding(.bottom, 12)
            }
        }
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(Text(isPlacing
            ? "已开启点击放置：点房间墙面放窗户、门或风口，点地面放座位；拖动仍可旋转房间"
            : "拖动旋转房间，捏合缩放"))
        .accessibilityIdentifier("roomRealityView")
    }

    /// Resolves one placement tap: hit-test the named wall/floor collision
    /// boxes, convert the scene-space hit into root-local display metres
    /// (undoing the orbit transform), then into draft coordinates. A tap
    /// that misses every named box is dropped — the patch is never forced
    /// onto the nearest wall.
    private func handlePlacementTap(at location: CGPoint) {
        guard let content = realityContent else { return }
        let hits = content.hitTest(point: location, in: .local, query: .all, mask: .all)
        // Walls and floor carry "placement.*" names; the first named hit wins.
        guard let hit = hits.first(where: { $0.entity.name.hasPrefix("placement.") }) else { return }
        // Entity has no `ancestors` collection: walk `parent` up to the room
        // root so the hit position can be converted into root-local metres.
        var node: Entity? = hit.entity
        var root: Entity?
        while let current = node {
            if current.name == RoomEntityBuilder.rootName {
                root = current
                break
            }
            node = current.parent
        }
        guard let root else { return }
        // Hit position is scene-space; convert into the root's local frame,
        // where the schematic meshes were placed in centered display metres.
        let local = root.convert(position: SIMD3<Float>(hit.position), from: nil)
        let sizeXM = scene.sizeXM
        let sizeYM = scene.sizeYM
        let sizeZM = scene.sizeZM
        if hit.entity.name == PlacementGeometry.floorEntityName {
            let floor = PlacementGeometry.floorSurface(
                displayX: Double(local.x),
                displayY: Double(local.y),
                displayZ: Double(local.z),
                sizeXM: sizeXM,
                sizeYM: sizeYM,
                sizeZM: sizeZM
            )
            onTapSurface?(.floor(xM: floor.xM, yM: floor.yM))
        } else {
            // "placement.wall.<rawValue>"; an unknown suffix is dropped.
            let raw = hit.entity.name
                .dropFirst("placement.wall.".count)
            guard let wall = WallFace(rawValue: String(raw)) else { return }
            let surface = PlacementGeometry.wallSurface(
                wall: wall,
                displayX: Double(local.x),
                displayY: Double(local.y),
                displayZ: Double(local.z),
                sizeXM: sizeXM,
                sizeYM: sizeYM,
                sizeZM: sizeZM
            )
            onTapSurface?(.wall(wall, sM: surface.sM, zM: surface.zM))
        }
    }

    private var accessibilityText: String {
        var text = scene.accessibilitySummary
        if let field, field.quality == "passed", let minC = field.stats.minC, let maxC = field.stats.maxC {
            text += "，坐姿高度温度切片 \(UserFacingCopy.displayNumber(minC)) 到 \(UserFacingCopy.displayNumber(maxC)) 摄氏度（质量通过）"
        }
        if let flow, flow.quality == "passed", let maxMag = flow.stats.maxMag {
            text += "，稳态气流箭头、流线和循环圆点，最大风速 \(UserFacingCopy.displayNumber(maxMag)) 米每秒，圆点是示意流向，不是开机降温"
        }
        // Per-seat L2 temperatures reach VoiceOver users too; the in-scene
        // flat labels are 3D graphics they cannot read.
        let seatTemps = scene.seats.compactMap { seat -> String? in
            guard let sample = seatSamples?.first(where: { $0.id == seat.id }) else { return nil }
            return "\(seat.displayName) \(UserFacingCopy.displayNumber(sample.tC)) 摄氏度"
        }
        if !seatTemps.isEmpty {
            text += "，座位气温 " + seatTemps.joined(separator: "、")
        }
        return text
    }
}
