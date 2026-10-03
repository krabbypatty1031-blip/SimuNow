import SwiftUI
import SimuCore
import SimuSimulation

@MainActor public struct SuggestionCardsView: View {
    let store: WorkspaceStore
    let onDirection: () -> Void
    let onObject: (UUID) -> Void
    @State private var cards: [SuggestionCard] = []
    public init(store: WorkspaceStore, onDirection: @escaping () -> Void, onObject: @escaping (UUID) -> Void) {
        self.store = store; self.onDirection = onDirection; self.onObject = onObject
    }
    private var input: SuggestionInput { .init(request: store.preview.currentRequest, result: store.preview.currentResult) }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if input.result == nil { Text("先生成与当前输入匹配的有效规则结果；过期或失败结果不生成当前建议。").font(.caption).foregroundStyle(.secondary) }
            ForEach(cards.filter { $0.identity == input.result?.identity }) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Label(targetName(card.seatID), systemImage: "lightbulb")
                    Text(card.message).font(.callout)
                    Button("定位关注点") { onObject(card.sampleID ?? card.seatID) }
                    if let obstacle = card.obstacleID { Button("查看遮挡家具") { onObject(obstacle) } }
                    DisclosureGroup("查看建议依据") {
                        Text("规则 \(card.ruleID) v\(card.ruleVersion)")
                        Text("档案 \(card.profileID) v\(card.profileVersion)")
                        Text("Run \(card.identity.runID) · 输入 \(card.identity.inputHash)").textSelection(.enabled)
                        if let sample = card.sampleID { Text("采样点 \(sample)") }
                        if let obstacle = card.obstacleID { Text("遮挡家具：\(store.project?.geometry.obstacles.first { $0.id == obstacle }?.name ?? obstacle.uuidString)") }
                    }.font(.caption)
                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if !cards.isEmpty, input.result != nil { Button("调整方向后重新比较", action: onDirection) }
        }.task(id: input) {
            cards = []
            guard let request = input.request, let result = input.result else { return }
            let worker = Task.detached { try PreviewRecommendationRules.suggestions(request: request, result: result, currentInputHash: request.identity.inputHash) }
            let built = try? await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            if !Task.isCancelled { cards = built ?? [] }
        }
    }
    private func targetName(_ id: UUID) -> String { store.currentScenario?.inputs.usage.seats.first { $0.id == id }?.name ?? "关注点" }
}
private struct SuggestionInput: Equatable { let request: LocalAnalysisRequest?; let result: LocalAnalysisResult? }
