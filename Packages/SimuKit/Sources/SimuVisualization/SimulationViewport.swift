import SwiftUI
import SimuCore
import SimuDesignSystem

/// Room viewport: real draft geometry when the model has it, an honest empty
/// state when it does not. No illustrative field is presented as CFD; the
/// temperature slice arrives with a quality-passed field in P4-05c.
public struct SimulationViewport: View {
    private let draft: ProjectDraft?

    public init(draft: ProjectDraft?) {
        self.draft = draft
    }

    public var body: some View {
        // No geometry means no honest room box; a fake room is never drawn.
        if let scene = draft.flatMap(RoomScene.init(draft:)) {
            RoomWireframeView(scene: scene)
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
