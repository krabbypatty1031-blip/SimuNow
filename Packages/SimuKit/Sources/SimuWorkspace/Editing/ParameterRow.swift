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
        case .known(_, let source, _):
            LabeledContent(label) {
                HStack(spacing: 4) {
                    TextField("数值", value: knownValueBinding, format: .number)
                        .labelsHidden()
                        .accessibilityLabel("\(label)，单位 \(Q.unit)")
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    Text(InputPresentation.unitTitle(Q.unit)).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("数值来源 · \(InputPresentation.sourceTitle(source.kind))") {
                SourceEditor(label: "来自哪里", source: sourceBinding)
                Button("暂不填写这个数值") { parameter = .unknown(reason: "") ; draft = "" ; entering = false }
                    .font(.caption)
            }
            .font(.caption).foregroundStyle(.secondary)
        case .unknown(let reason):
            LabeledContent(label) {
                if entering {
                    HStack(spacing: 4) {
                        TextField("输入数值", text: $draft)
                            .labelsHidden()
                            .accessibilityLabel("\(label)，单位 \(Q.unit)")
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text(InputPresentation.unitTitle(Q.unit)).foregroundStyle(.secondary)
                        Button("确定") { commitDraft() }.disabled(Double(draft.trimmingCharacters(in: .whitespaces)) == nil)
                        Button("取消") { entering = false ; draft = "" }
                    }
                } else {
                    HStack {
                        Text("待填写").foregroundStyle(.secondary)
                        Button("填写…") { entering = true ; draft = "" }
                    }
                }
            }
            if !entering {
                DisclosureGroup("为什么还没填写") {
                    TextField("例如：尚未测量（必填）", text: reasonBinding).font(.caption)
                    if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("请说明原因，便于之后补齐。").font(.caption2).foregroundStyle(.orange)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
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
            Text("设备说明书").tag(ParameterSource.manufacturer)
            Text("模板预设").tag(ParameterSource.preset)
            Text("扫描").tag(ParameterSource.scan)
            Text("自己填写").tag(ParameterSource.user)
            Text("暂用假设").tag(ParameterSource.assumed)
        }
        .pickerStyle(.menu)
        .font(.caption)
        switch source.kind {
        case .measured, .manufacturer, .preset:
            TextField("资料名称或出处（必填）", text: referenceBinding).font(.caption)
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
                    .labelsHidden()
                    .accessibilityLabel("\(label)，单位 \(unit)")
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}
