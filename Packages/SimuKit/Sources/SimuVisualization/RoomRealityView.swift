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
    @State private var internalYaw: Double = ViewportOrbit.defaultYaw
    @State private var orbit = ViewportOrbit()
    @State private var dragStart: (yaw: Double, pitch: Double)?
    @State private var pinchStart: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.userFacingCopy) private var copy

    public init(
        scene: RoomScene,
        field: FieldSlice? = nil,
        flow: FlowOverlay? = nil,
        sharedPalette: SlicePalette? = nil,
        yaw: Binding<Double>? = nil,
        seatSamples: [SeatSample]? = nil
    ) {
        self.scene = scene
        self.field = field
        self.flow = flow
        self.sharedPalette = sharedPalette
        self.seatSamples = seatSamples
        self.externalYaw = yaw
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
            seatKey: (seatSamples.map { samples in
                samples
                    .map { "\($0.id):\($0.tC)" }
                    .sorted()
                    .joined(separator: ",")
            } ?? "") + "|lang:" + copy.language.rawValue
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
            let root = await RoomEntityBuilder.makeRoot(
                scene: scene,
                field: field,
                palette: palette,
                flow: flow,
                seatSamples: seatSamples,
                copy: copy
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
        .accessibilityHint(Text(copy.orbitRoomHint))
        .accessibilityIdentifier("roomRealityView")
    }

    private var accessibilityText: String {
        var text = scene.accessibilitySummary(copy: copy)
        if let field, field.quality == "passed", let minC = field.stats.minC, let maxC = field.stats.maxC {
            text += copy.sliceAccessibility(
                min: UserFacingCopy.displayNumber(minC),
                max: UserFacingCopy.displayNumber(maxC)
            )
        }
        if let flow, flow.quality == "passed", let maxMag = flow.stats.maxMag {
            text += copy.flowAccessibility(max: UserFacingCopy.displayNumber(maxMag))
        }
        let seatTemps = scene.seats.compactMap { seat -> String? in
            guard let sample = seatSamples?.first(where: { $0.id == seat.id }) else { return nil }
            return copy.seatTemperatureLabel(name: seat.displayName, value: UserFacingCopy.displayNumber(sample.tC))
        }
        if !seatTemps.isEmpty {
            text += copy.seatTemperaturesAccessibility(seatTemps.joined(separator: copy.listSeparator))
        }
        return text
    }
}
