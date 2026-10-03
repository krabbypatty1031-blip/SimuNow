import Foundation
import SwiftUI
import SimuCore

public struct ParameterSummaryItem: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case unknown, assumption, preset, missingSource, unsupported }
    public let path: String
    public let kind: Kind
    public let detail: String
    public var id: String { path }
}

public enum ParameterAssumptions {
    /// Resolves only registered payloads. Unsupported extension data is never rewritten.
    public static func collect(from project: ProjectDocument, registry: ModelRegistry = .builtIn) throws -> [ParameterSummaryItem] {
        var items: [ParameterSummaryItem] = []
        func scan(_ node: JSONValue, path: String) throws {
            if let fields = node.fields {
                if fields["kind"] != nil, fields["payloadVersion"] != nil, fields["payload"] != nil {
                    let category = path.hasSuffix("/definition") ? "hvac" : path.hasPrefix("/geometry/obstacles/") ? "obstacle" : "room"
                    let record = try JSONTreeCoding.decode(ExtensionRecord.self, from: node)
                    if let payload = try registry.resolve(category: category, record: record) {
                        try scan(JSONTreeCoding.encode(payload), path: path + "/payload")
                    } else {
                        items.append(.init(path: path, kind: .unsupported, detail: "不支持的模型 \(record.kind)，原始参数保留，不能用于计算。"))
                    }
                    return
                }
                if node["state"]?.string == "unknown" {
                    items.append(.init(path: path, kind: .unknown, detail: node["reason"]?.string ?? "尚未提供原因"))
                    return
                }
                if node["state"]?.string == "known" {
                    let kind = node["source"]?["kind"]?.string ?? ""
                    let reference = node["source"]?["reference"]?.string ?? ""
                    let note = node["source"]?["note"]?.string ?? ""
                    let value = node["value"]?.double.map { String($0) } ?? "?"
                    let unit = node["unit"]?.string ?? ""
                    let prefix = "\(value) \(unit)"
                    if kind == "assumed" {
                        items.append(.init(path: path, kind: .assumption, detail: "\(prefix)；\(note.isEmpty ? "缺少假设说明" : note)\(reference.isEmpty ? "" : "；\(reference)")"))
                    } else if kind == "preset" {
                        items.append(.init(path: path, kind: .preset, detail: "\(prefix)；依据：\(reference.isEmpty ? "尚未提供" : reference)\(note.isEmpty ? "" : "；\(note)")"))
                    } else if ["measured", "manufacturer"].contains(kind), reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        items.append(.init(path: path, kind: .missingSource, detail: "\(prefix)；请补充来源依据。"))
                    }
                    return
                }
                for key in fields.keys.sorted() {
                    let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                    try scan(fields[key]!, path: path + "/" + escaped)
                }
            } else if let array = node.items {
                for (index, child) in array.enumerated() { try scan(child, path: path + "/\(index)") }
            }
        }
        try scan(JSONTreeCoding.encode(project), path: "")
        return items
    }
}

public struct ParameterAssumptionsView: View {
    private let project: ProjectDocument
    private let registry: ModelRegistry
    private let scenarioID: UUID?
    private let onLocate: (@MainActor (String) -> Void)?
    @State private var search = ""
    @State private var allScenarios = false
    @State private var selectedKind: ParameterSummaryItem.Kind?
    @State private var items: [ParameterSummaryItem] = []
    @State private var failed = false
    public init(project: ProjectDocument, registry: ModelRegistry = .builtIn, scenarioID: UUID? = nil,
                onLocate: (@MainActor (String) -> Void)? = nil) {
        self.project = project; self.registry = registry; self.scenarioID = scenarioID; self.onLocate = onLocate
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索对象、参数或来源", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("搜索未知与假设")
            Toggle("查看全部方案", isOn: $allScenarios)
            Picker("参数状态", selection: $selectedKind) {
                Text("全部状态").tag(Optional<ParameterSummaryItem.Kind>.none)
                ForEach([ParameterSummaryItem.Kind.unknown, .assumption, .preset, .missingSource, .unsupported], id: \.rawValue) { kind in
                    Text(label(kind)).tag(Optional(kind))
                }
            }
            Text(allScenarios ? "全项目范围；共享几何及各方案分别标明。" : "当前方案及共享几何；其他方案的未知不会计入此处。")
                .font(.caption).foregroundStyle(.secondary)
            if failed { Label("参数摘要读取失败，请检查项目格式。", systemImage: "exclamationmark.triangle") }
            else if filtered.isEmpty { Text("当前范围没有匹配条目。").foregroundStyle(.secondary) }
            ForEach(filtered) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(FieldNavigation.objectName(project: project, path: item.path)).font(.subheadline.bold())
                    Label(label(item.kind), systemImage: item.kind == .unknown ? "questionmark.circle" : "info.circle").font(.caption)
                    Text(item.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let onLocate, item.kind != .unsupported { Button("定位字段并编辑") { onLocate(item.path) } }
                    DisclosureGroup("诊断字段路径") { Text(item.path).font(.caption2).textSelection(.enabled) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).id(item.id)
            }
        }
        .task(id: project) {
            let source = project, registry = registry
            let task = Task.detached { try ParameterAssumptions.collect(from: source, registry: registry) }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                if !Task.isCancelled { items = value; failed = false }
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
    private var filtered: [ParameterSummaryItem] {
        items.filter { item in
            if !allScenarios, item.path.hasPrefix("/scenarios/") {
                let index = item.path.split(separator: "/").dropFirst().first.flatMap { Int($0) }
                guard let index, project.scenarios.indices.contains(index), project.scenarios[index].id == scenarioID else { return false }
            }
            if let selectedKind, item.kind != selectedKind { return false }
            return search.isEmpty || item.detail.localizedStandardContains(search) || ValidationPresentation.fieldPath(item.path).localizedStandardContains(search) || FieldNavigation.objectName(project: project, path: item.path).localizedStandardContains(search)
        }
    }
    private func label(_ kind: ParameterSummaryItem.Kind) -> String {
        switch kind { case .unknown: "未知参数"; case .assumption: "假设"; case .preset: "预设及依据"; case .missingSource: "待补充来源"; case .unsupported: "无法解释的扩展" }
    }
}
