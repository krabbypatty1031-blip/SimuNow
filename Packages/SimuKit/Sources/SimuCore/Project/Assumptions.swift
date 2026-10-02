import Foundation

/// Collects every unknown parameter (with reason) and every assumed value (with note)
/// from a project, so both the inspector and reports show the same honest list.
public enum AssumptionCollector {
    public static func items(in project: ProjectDocument) -> [String] {
        guard let node = try? JSONTreeCoding.encode(project) else { return [] }
        var items: [String] = []
        walk(node, path: "", into: &items)
        return items.sorted()
    }

    private static func walk(_ node: JSONValue, path: String, into items: inout [String]) {
        if node["state"]?.string == "unknown", let reason = node["reason"]?.string {
            items.append("\(path)：未知 — \(reason)")
        }
        if node["source"]?["kind"]?.string == "assumed", let note = node["source"]?["note"]?.string {
            items.append("\(path)：假设 — \(note)")
        }
        if let fields = node.fields {
            for key in fields.keys.sorted() where key != "payload" {
                walk(fields[key]!, path: path + "/" + key, into: &items)
            }
        } else if let array = node.items {
            for (index, item) in array.enumerated() { walk(item, path: path + "/\(index)", into: &items) }
        }
    }
}
