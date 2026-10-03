import SwiftUI
import SimuCore
import SimuDesignSystem

/// Room viewport: real draft geometry when the model has it, an honest empty
/// state when it does not. On macOS 15 / iOS 18 this is a viewer-only
/// RealityKit room; older systems keep the Canvas wireframe. A quality-passed
/// field slice paints the seat-height plane; without a field no colour is
/// drawn - an illustrative rainbow is never presented as CFD.
public struct SimulationViewport: View {
    private let draft: ProjectDraft?
    private let field: FieldSlice?
    private let flow: FlowOverlay?
    private let sharedPalette: SlicePalette?
    private let yaw: Binding<Double>?

    public init(
        draft: ProjectDraft?,
        field: FieldSlice? = nil,
        flow: FlowOverlay? = nil,
        sharedPalette: SlicePalette? = nil,
        yaw: Binding<Double>? = nil
    ) {
        self.draft = draft
        self.field = field
        self.flow = flow
        self.sharedPalette = sharedPalette
        self.yaw = yaw
    }

    public var body: some View {
        // No geometry means no honest room box; a fake room is never drawn.
        if let scene = draft.flatMap(RoomScene.init(draft:)) {
            // RealityView is macOS 15 / iOS 18. Older systems keep the Canvas
            // wireframe so the deployment floor stays macOS 14 / iOS 17.
            if #available(macOS 15.0, iOS 18.0, *) {
                RoomRealityView(scene: scene, field: field, flow: flow, sharedPalette: sharedPalette, yaw: yaw)
            } else {
                RoomWireframeView(scene: scene, field: field, flow: flow, sharedPalette: sharedPalette, yaw: yaw)
            }
        } else {
            EmptyStateView(
                "布置房间",
                symbol: "cube.transparent",
                message: "先填写房间的长宽高。没有完整房间时不会画示意图。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("simulationViewport")
        }
    }
}
