import SwiftUI
import SimuCore
import SimuDesignSystem

/// Room viewport: real draft geometry when the model has it, an honest empty
/// state when it does not. A quality-passed field slice paints the seat
/// height plane with its own legend; without a field no colour is drawn -
/// an illustrative rainbow is never presented as CFD.
public struct SimulationViewport: View {
    private let draft: ProjectDraft?
    private let field: FieldSlice?
    private let sharedPalette: SlicePalette?
    private let yaw: Binding<Double>?

    public init(draft: ProjectDraft?, field: FieldSlice? = nil, sharedPalette: SlicePalette? = nil, yaw: Binding<Double>? = nil) {
        self.draft = draft
        self.field = field
        self.sharedPalette = sharedPalette
        self.yaw = yaw
    }

    public var body: some View {
        // No geometry means no honest room box; a fake room is never drawn.
        if let scene = draft.flatMap(RoomScene.init(draft:)) {
            RoomWireframeView(scene: scene, field: field, sharedPalette: sharedPalette, yaw: yaw)
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
