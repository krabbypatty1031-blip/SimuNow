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
    public init(project: ProjectDocument, registry: ModelRegistry = .builtIn) {
        self.project = project; self.registry = registry
    }
    public var body: some View {
        if let items = try? ParameterAssumptions.collect(from: project, registry: registry) {
            if items.isEmpty { Text("没有未知参数、假设或预设。").foregroundStyle(.secondary) }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Label(label(item.kind), systemImage: item.kind == .unknown ? "questionmark.circle" : "info.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(item.detail).font(.caption)
                    Text(item.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(.vertical, 3)
            }
        } else {
            Label("参数摘要读取失败，请检查项目格式。", systemImage: "exclamationmark.triangle")
        }
    }
    private func label(_ kind: ParameterSummaryItem.Kind) -> String {
        switch kind {
        case .unknown: "未知参数"
        case .assumption: "假设"
        case .preset: "预设及依据"
        case .missingSource: "待补充来源"
        case .unsupported: "无法解释的扩展"
        }
    }
}
