import RealityKit
import SwiftUI
import SimuCore

/// Viewer-only RealityKit room: orbit, schematic AC / openings / desks /
/// seated people, a quality-gated seat-height slice, and optional steady
/// flow arrows. Add/delete in the inspector rebuilds this view. There is
/// no click-to-select and no 3D drag handle — those belong to later schemes.
@available(macOS 15.0, iOS 18.0, *)
public struct RoomRealityView: View {
    private let scene: RoomScene
    private let field: FieldSlice?
    private let flow: FlowOverlay?
    private let sharedPalette: SlicePalette?
    private let externalYaw: Binding<Double>?
    @State private var internalYaw: Double = ViewportOrbit.defaultYaw
    @State private var orbit = ViewportOrbit()
    @State private var dragStart: (yaw: Double, pitch: Double)?
    @State private var pinchStart: Double?

    public init(
        scene: RoomScene,
        field: FieldSlice? = nil,
        flow: FlowOverlay? = nil,
        sharedPalette: SlicePalette? = nil,
        yaw: Binding<Double>? = nil
    ) {
        self.scene = scene
        self.field = field
        self.flow = flow
        self.sharedPalette = sharedPalette
        self.externalYaw = yaw
    }

    private var yaw: Binding<Double> {
        externalYaw ?? $internalYaw
    }

    private var palette: SlicePalette? {
        SlicePalette.resolved(field: field, shared: sharedPalette)
    }

    /// Rebuild geometry only when the draft or field changes. Drag updates
    /// the root transform in `update` and must not recreate meshes.
    private var buildID: String {
        RoomDisplayLayout.buildID(
            scene: scene,
            fieldHash: field?.inputHash,
            paletteKey: palette.map { "\($0.minC):\($0.maxC)" },
            flowHash: flow?.inputHash
        )
    }

    public var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = await RoomEntityBuilder.makeRoot(scene: scene, field: field, palette: palette, flow: flow)
            RoomEntityBuilder.applyOrbit(root, scene: scene, orbit: orbit)
            content.add(root)
            content.cameraTarget = root
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == RoomEntityBuilder.rootName }) else {
                return
            }
            RoomEntityBuilder.applyOrbit(root, scene: scene, orbit: orbit)
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
        .overlay(alignment: .topLeading) {
            if !scene.seats.isEmpty {
                Text(scene.seatDisplayNames.joined(separator: " · "))
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if palette != nil || flow != nil {
                ViewportLegend(palette: palette, flow: flow)
                    .padding(.bottom, 12)
            }
        }
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(Text("拖动旋转房间，捏合缩放"))
        .accessibilityIdentifier("roomRealityView")
    }

    private var accessibilityText: String {
        var text = scene.accessibilitySummary
        if let field, field.quality == "passed", let minC = field.stats.minC, let maxC = field.stats.maxC {
            text += "，坐姿高度温度切片 \(UserFacingCopy.displayNumber(minC)) 到 \(UserFacingCopy.displayNumber(maxC)) 摄氏度（质量通过）"
        }
        if let flow, flow.quality == "passed", let maxMag = flow.stats.maxMag {
            text += "，稳态气流箭头和流线，最大风速 \(UserFacingCopy.displayNumber(maxMag)) 米每秒，箭头已放大，不是开机降温"
        }
        return text
    }
}
