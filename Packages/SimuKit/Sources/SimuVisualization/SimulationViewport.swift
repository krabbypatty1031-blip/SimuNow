import SwiftUI
import SimuDesignSystem

/// Replace with a renderer adapter in P4; no illustrative field is presented as CFD.
public struct SimulationViewport: View {
    private let showsIncompleteModel: Bool

    public init(showsIncompleteModel: Bool = true) {
        self.showsIncompleteModel = showsIncompleteModel
    }

    public var body: some View {
        EmptyStateView(
            "房间工作区",
            symbol: "cube.transparent",
            message: showsIncompleteModel
                ? "模型不完整。先在属性面板填写房间尺寸与设备，计算引擎尚未接入。"
                : "房间输入已齐全。计算任务在引擎接入前不可用。"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("simulationViewport")
    }
}
