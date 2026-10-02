import SwiftUI
import SimuCore
import SimuDesignSystem
import SimuVisualization

public struct WorkspaceView: View {
    @State private var store: WorkspaceStore

    public init(store: WorkspaceStore) {
        self._store = State(initialValue: store)
    }

    public var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(WorkspaceDestination.allCases, selection: $store.selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("SimuNow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
                .navigationTitle(store.selection?.title ?? "SimuNow")
        }
        #if os(macOS)
        .inspector(isPresented: .constant(true)) {
            InspectorPlaceholder()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection ?? .workspace {
        case .workspace:
            SimulationViewport()
        case .scenarios:
            EmptyStateView("暂无方案", symbol: "square.stack.3d.up", message: "建立基准方案后，比较候选配置的舒适、能耗与成本。")
        case .runs:
            EmptyStateView("暂无计算任务", symbol: "waveform.path", message: "计算引擎接入后，这里显示任务进度与质量状态。")
        case .reports:
            EmptyStateView("暂无报告", symbol: "doc.text", message: "通过质量检查的结果可用于生成建议报告。")
        }
    }
}

private struct InspectorPlaceholder: View {
    var body: some View {
        Form {
            Section("项目") {
                LabeledContent("状态", value: "尚未载入")
            }
            Section("属性") {
                Text("选择房间、空调或座位后编辑参数。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
