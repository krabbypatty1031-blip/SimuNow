import SwiftUI
import SimuDesignSystem

/// Replace with a renderer adapter in P2/P4; no illustrative field is presented as CFD.
public struct SimulationViewport: View {
    public init() {}

    public var body: some View {
        EmptyStateView(
            "房间工作区",
            symbol: "cube.transparent",
            message: "创建或导入房间后，在这里编辑空间并查看计算结果。"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("simulationViewport")
    }
}
