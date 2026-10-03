import SwiftUI
import SimuCore

/// Values are always reachable; evidence is progressively disclosed without rewriting it.
public struct PhysicalParameterEditor<Q: QuantityTag>: View {
    private let title: String
    private let range: ParameterValueRange
    private let percentage: Bool
    @Binding private var draft: PhysicalParameterDraft
    @State private var showEvidence = false
    @State private var percentageInput: String?
    @FocusState private var focused: Bool
    @SwiftUI.Environment(\.editorFocus) private var focus
    @SwiftUI.Environment(\.editorEntityID) private var entityID
    @SwiftUI.Environment(\.editorFieldOrdinal) private var ordinal
    public init(_ title: String, draft: Binding<PhysicalParameterDraft>, quantity: Q.Type,
                range: ParameterValueRange = .unbounded, percentage: Bool = false) {
        self.title = title; _draft = draft; self.range = range; self.percentage = percentage
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer()
                    Toggle("已知", isOn: $draft.isKnown).toggleStyle(.checkboxCompat)
                }
                VStack(alignment: .leading) { Text(title); Toggle("已知数值", isOn: $draft.isKnown) }
            }
            if draft.isKnown {
                HStack(alignment: .firstTextBaseline) {
                    TextField(title, text: valueBinding).labelsHidden().textFieldStyle(.roundedBorder)
                        .focused($focused).accessibilityLabel(title + "，单位 " + displayUnit)
                    Text(displayUnit).font(.subheadline).foregroundStyle(.secondary)
                }
                Label(InputDisplay.source(draft.sourceKind), systemImage: "doc.text")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("未知 · 可以保留草稿", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(draft.isKnown ? "来源与不确定区间" : "未知原因", isExpanded: $showEvidence) {
                VStack(alignment: .leading, spacing: 10) {
                    if draft.isKnown {
                        Picker("来源", selection: $draft.sourceKind) {
                            ForEach(sourceKinds, id: \.rawValue) { Text(InputDisplay.source($0)).tag($0) }
                        }
                        EditorTextField(title: "来源依据 / 参考链接", text: $draft.reference)
                        EditorTextField(title: "备注 / 假设说明", text: $draft.note)
                        Toggle("记录不确定性上下界", isOn: $draft.hasUncertainty)
                        if draft.hasUncertainty {
                            EditorTextField(title: "下界（\(InputDisplay.unit(Q.unit))）", text: $draft.lowerText)
                            EditorTextField(title: "上界（\(InputDisplay.unit(Q.unit))）", text: $draft.upperText)
                            EditorTextField(title: "上下界含义", text: $draft.uncertaintyMeaning)
                        }
                        Text("范围：\(range.description)。改变数值会标为用户输入；原参考链接保留，请核实依据。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else { EditorTextField(title: "未知原因", text: $draft.unknownReason) }
                }.padding(.top, 8)
            }
        }
        .padding(12).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .id(EditorFieldAnchor(entityID: entityID, field: title, ordinal: ordinal))
        .onChange(of: focus, initial: true) { _, value in
            if value.field == title, value.entityID == nil || value.entityID == entityID,
               value.ordinal == ordinal { focused = true; showEvidence = true }
        }
        .onChange(of: draft.valueText) { _, value in
            guard percentage, let percentageInput else { return }
            let converted = Double(percentageInput).map { String($0 / 100) } ?? percentageInput
            if converted != value { self.percentageInput = nil }
        }
    }
    private var displayUnit: String { percentage ? "%" : InputDisplay.unit(Q.unit) }
    private var valueBinding: Binding<String> {
        Binding(get: {
            if percentage, let percentageInput { return percentageInput }
            guard percentage, let value = Double(draft.valueText), value.isFinite else { return draft.valueText }
            return (value * 100).formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...6)))
        }, set: { text in
            if percentage { percentageInput = text }
            if percentage, let value = Double(text), value.isFinite { draft.enterValue(String(value / 100)) }
            else { draft.enterValue(text) }
        })
    }
    private var error: String? {
        do { let _: PhysicalParameter<Q> = try draft.parameter(range: range); return nil }
        catch { return error.localizedDescription }
    }
    private var sourceKinds: [ParameterSource] { [.user, .measured, .manufacturer, .preset, .assumed, .scan] }
}

private struct CheckboxCompatibleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        #else
        Toggle(isOn: configuration.$isOn) { configuration.label }
        #endif
    }
}
private extension ToggleStyle where Self == CheckboxCompatibleStyle {
    static var checkboxCompat: CheckboxCompatibleStyle { .init() }
}
