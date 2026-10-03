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

    public init(draft: ProjectDraft?, field: FieldSlice? = nil) {
        self.draft = draft
        self.field = field
    }

    public var body: some View {
        // No geometry means no honest room box; a fake room is never drawn.
        if let scene = draft.flatMap(RoomScene.init(draft:)) {
            RoomWireframeView(scene: scene, field: field)
        } else {
            EmptyStateView(
                "房间工作区",
                symbol: "cube.transparent",
                message: "模型不完整。先在属性面板填写房间尺寸与设备，计算引擎尚未接入。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("simulationViewport")
        }
    }
}
