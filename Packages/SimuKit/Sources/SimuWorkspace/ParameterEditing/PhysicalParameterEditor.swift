import SwiftUI
import SimuCore

/// Reusable form fields. Draft validation is displayed locally, with submission owned by the parent.
public struct PhysicalParameterEditor<Q: QuantityTag>: View {
    private let title: String
    private let range: ParameterValueRange
    @Binding private var draft: PhysicalParameterDraft
    public init(_ title: String, draft: Binding<PhysicalParameterDraft>, quantity: Q.Type,
                range: ParameterValueRange = .unbounded) {
        self.title = title; _draft = draft; self.range = range
    }
    public var body: some View {
        DisclosureGroup {
            Toggle("已知数值", isOn: $draft.isKnown)
            if draft.isKnown {
                TextField("数值（\(Q.unit)）", text: Binding(get: { draft.valueText }, set: { draft.enterValue($0) }))
                    .accessibilityLabel("\(title)，单位 \(Q.unit)")
                Picker("来源", selection: $draft.sourceKind) {
                    ForEach(sourceKinds, id: \.rawValue) { Text(sourceLabel($0)).tag($0) }
                }
                TextField("来源依据 / 参考链接", text: $draft.reference, axis: .vertical)
                TextField("备注 / 假设说明", text: $draft.note, axis: .vertical)
                Toggle("记录不确定性上下界", isOn: $draft.hasUncertainty)
                if draft.hasUncertainty {
                    TextField("下界（\(Q.unit)）", text: $draft.lowerText)
                    TextField("上界（\(Q.unit)）", text: $draft.upperText)
                    TextField("上下界含义", text: $draft.uncertaintyMeaning, axis: .vertical)
                }
                Text("范围：\(range.description)；修改数值后来源改为用户输入，请重新核实依据。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("未知原因", text: $draft.unknownReason, axis: .vertical)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        } label: {
            LabeledContent(title) { Text(summary).foregroundStyle(.secondary) }
        }
    }
    private var summary: String { draft.isKnown ? "\(draft.valueText.isEmpty ? "待输入" : draft.valueText) \(Q.unit)" : "未知" }
    private var error: String? {
        do { let _: PhysicalParameter<Q> = try draft.parameter(range: range); return nil }
        catch { return error.localizedDescription }
    }
    private var sourceKinds: [ParameterSource] { [.user, .measured, .manufacturer, .preset, .assumed, .scan] }
    private func sourceLabel(_ kind: ParameterSource) -> String {
        switch kind {
        case .user: "用户输入"
        case .measured: "实测"
        case .manufacturer: "厂家资料"
        case .preset: "有来源的预设"
        case .assumed: "假设"
        case .scan: "扫描"
        }
    }
}
