import SwiftUI
import SimuCore

/// The single editing control for every physical parameter: value + fixed unit + source, or explicit unknown + reason.
/// Toggling to "known" never silently inserts a value: the user must commit a parseable number first.
public struct ParameterRow<Q: QuantityTag>: View {
    let label: String
    @Binding var parameter: PhysicalParameter<Q>
    @State private var draft = ""
    @State private var entering = false

    public init(_ label: String, _ parameter: Binding<PhysicalParameter<Q>>) {
        self.label = label
        self._parameter = parameter
    }

    public var body: some View {
        switch parameter {
        case .known(let value, let source, _):
            LabeledContent(label) {
                HStack(spacing: 4) {
                    TextField("数值", value: knownValueBinding, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    Text(Q.unit).foregroundStyle(.secondary)
                }
            }
            SourceEditor(label: "来源", source: sourceBinding)
            Button("标记为未知") { parameter = .unknown(reason: "") ; draft = "" ; entering = false }
                .font(.caption)
        case .unknown(let reason):
            LabeledContent(label) {
                if entering {
                    HStack(spacing: 4) {
                        TextField("输入数值", text: $draft)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text(Q.unit).foregroundStyle(.secondary)
                        Button("确定") { commitDraft() }.disabled(Double(draft.trimmingCharacters(in: .whitespaces)) == nil)
                        Button("取消") { entering = false ; draft = "" }
                    }
                } else {
                    HStack {
                        Text("未知").foregroundStyle(.secondary)
                        Button("填写…") { entering = true ; draft = "" }
                    }
                }
            }
            if !entering {
                TextField("未知原因（必填）", text: reasonBinding)
                    .font(.caption)
                if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("需要说明原因").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var knownValueBinding: Binding<Double> {
        Binding(get: { parameter.value ?? 0 }, set: { newValue in
            if case .known(_, let source, let uncertainty) = parameter {
                parameter = .known(value: newValue, source: source, uncertainty: uncertainty)
            }
        })
    }

    private var sourceBinding: Binding<SourceRecord> {
        Binding(get: {
            if case .known(_, let source, _) = parameter { return source }
            return SourceRecord(kind: .user)
        }, set: { newSource in
            if case .known(let value, _, let uncertainty) = parameter {
                parameter = .known(value: value, source: newSource, uncertainty: uncertainty)
            }
        })
    }

    private var reasonBinding: Binding<String> {
        Binding(get: {
            if case .unknown(let reason) = parameter { return reason }
            return ""
        }, set: { parameter = .unknown(reason: $0) })
    }

    private func commitDraft() {
        guard let value = Double(draft.trimmingCharacters(in: .whitespaces)), value.isFinite else { return }
        parameter = .known(value: value, source: SourceRecord(kind: .user))
        entering = false
        draft = ""
    }
}

/// Source kind + mandatory reference/note for a known parameter.
public struct SourceEditor: View {
    let label: String
    @Binding var source: SourceRecord

    public var body: some View {
        Picker(label, selection: $source.kind) {
            Text("实测").tag(ParameterSource.measured)
            Text("厂商").tag(ParameterSource.manufacturer)
            Text("预设").tag(ParameterSource.preset)
            Text("扫描").tag(ParameterSource.scan)
            Text("用户").tag(ParameterSource.user)
            Text("假设").tag(ParameterSource.assumed)
        }
        .pickerStyle(.menu)
        .font(.caption)
        switch source.kind {
        case .measured, .manufacturer, .preset:
            TextField("引用（必填）", text: referenceBinding).font(.caption)
        case .assumed:
            TextField("假设说明（必填）", text: noteBinding).font(.caption)
        case .scan, .user:
            TextField("备注（可选）", text: noteBinding).font(.caption)
        }
    }

    private var referenceBinding: Binding<String> {
        Binding(get: { source.reference ?? "" }, set: { source.reference = $0.isEmpty ? nil : $0 })
    }
    private var noteBinding: Binding<String> {
        Binding(get: { source.note ?? "" }, set: { source.note = $0.isEmpty ? nil : $0 })
    }
}

/// Simple non-physical string / number rows used across forms.
public struct UnitNumberRow: View {
    let label: String
    let unit: String
    @Binding var value: Double
    public init(_ label: String, unit: String, value: Binding<Double>) {
        self.label = label; self.unit = unit; self._value = value
    }
    public var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("数值", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}
