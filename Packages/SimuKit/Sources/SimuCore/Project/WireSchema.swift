import Foundation

/// Validates the emitted subset of JSON Schema 2020-12. Not a general schema engine.
/// Unsupported assertion keywords fail closed; annotations do not affect validation.
public enum WireSchema {
    public static func validate(_ value: JSONValue, schema: JSONValue) throws {
        try check(value, schema: schema, root: schema, path: "")
    }
    private static let annotations: Set<String> = ["$schema","$id","$defs","title","description","default","examples"]
    private static let assertions: Set<String> = ["$ref","type","required","properties","additionalProperties","items","const","enum","anyOf","allOf","if","then","else","minimum","maximum","exclusiveMinimum","exclusiveMaximum","minLength","maxLength","pattern","format","minItems","maxItems"]
    private static func fail(_ path: String, _ message: String) -> ProjectDataError { .contract("\(path): \(message)") }
    private static func check(_ value: JSONValue, schema: JSONValue, root: JSONValue, path: String) throws {
        if schema == .bool(true) { return }
        if schema == .bool(false) { throw fail(path,"forbidden") }
        guard let s = schema.fields else { throw fail(path,"invalid schema") }
        guard Set(s.keys).subtracting(annotations.union(assertions)).isEmpty else { throw fail(path,"unsupported schema assertion") }
        if let ref = s["$ref"]?.string {
            guard ref.hasPrefix("#/$defs/"), let target = root["$defs"]?[String(ref.dropFirst(8))] else { throw fail(path,"unresolved ref") }
            try check(value,schema:target,root:root,path:path)
        }
        if let choices = s["anyOf"]?.items {
            guard choices.contains(where: { (try? check(value,schema:$0,root:root,path:path)) != nil }) else { throw fail(path,"no matching shape") }
        }
        if let choices = s["allOf"]?.items { for choice in choices { try check(value,schema:choice,root:root,path:path) } }
        if let condition = s["if"] {
            let branch = (try? check(value,schema:condition,root:root,path:path)) != nil ? s["then"] : s["else"]
            if let branch { try check(value,schema:branch,root:root,path:path) }
        }
        if let constant = s["const"], !equivalent(value,constant) { throw fail(path,"constant mismatch") }
        if let values = s["enum"]?.items, !values.contains(where: { equivalent(value,$0) }) { throw fail(path,"unknown enum") }
        if let typeNode = s["type"], typeNode.string == nil { throw fail(path,"unsupported schema type form") }
        if let type = s["type"]?.string {
            let matches: Bool
            switch (type,value) {
            case ("object",.object), ("array",.array), ("string",.string), ("boolean",.bool), ("null",.null): matches = true
            case ("number",.number): matches = value.double?.isFinite == true
            case ("integer",.number): matches = value.double.map { $0.isFinite && $0.rounded() == $0 } == true
            default: matches = false
            }
            guard matches else { throw fail(path,"expected \(type)") }
        }
        if let fields = value.fields {
            let properties = s["properties"]?.fields ?? [:]
            for key in s["required"]?.items?.compactMap(\.string) ?? [] {
                guard fields[key] != nil else { throw fail(path + "/" + key,"missing") }
            }
            for (key,node) in fields {
                let escaped = key.replacingOccurrences(of:"~",with:"~0").replacingOccurrences(of:"/",with:"~1")
                if let sub = properties[key] { try check(node,schema:sub,root:root,path:path + "/" + escaped) }
                else if let additional = s["additionalProperties"] { try check(node,schema:additional,root:root,path:path + "/" + escaped) }
            }
        }
        if let items = value.items {
            if let n = s["minItems"]?.double, Double(items.count) < n { throw fail(path,"array too short") }
            if let n = s["maxItems"]?.double, Double(items.count) > n { throw fail(path,"array too long") }
            if let sub = s["items"] { for (i,item) in items.enumerated() { try check(item,schema:sub,root:root,path:path + "/\(i)") } }
        }
        if let text = value.string {
            if let n = s["minLength"]?.double, Double(text.unicodeScalars.count) < n { throw fail(path,"string too short") }
            if let n = s["maxLength"]?.double, Double(text.unicodeScalars.count) > n { throw fail(path,"string too long") }
            if let pattern = s["pattern"]?.string, text.range(of: pattern, options: .regularExpression) == nil { throw fail(path,"pattern") }
            if let format = s["format"]?.string {
                guard format == "uuid", text.range(of:"^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$",options:.regularExpression) != nil, UUID(uuidString: text) != nil else { throw fail(path,"format: \(format)") }
            }
        }
        if let number = value.double {
            if let n = s["minimum"]?.double, number < n { throw fail(path,"minimum") }
            if let n = s["maximum"]?.double, number > n { throw fail(path,"maximum") }
            if let n = s["exclusiveMinimum"]?.double, number <= n { throw fail(path,"exclusive minimum") }
            if let n = s["exclusiveMaximum"]?.double, number >= n { throw fail(path,"exclusive maximum") }
        }
    }
    private static func equivalent(_ a: JSONValue,_ b: JSONValue) -> Bool {
        if case .number = a, case .number = b { return a.double == b.double }
        return a == b
    }
}

enum ContractSchemas {
    static let project = load("project-document.schema")
    static let snapshot = load("scenario-input-snapshot.schema")
    private static func load(_ name: String) -> JSONValue {
        // Bundled generated resources are verified by check.sh contracts.
        guard let url = Bundle.module.url(forResource:name,withExtension:"json"),
              let data = try? Data(contentsOf:url), let schema = try? JSONValue(data:data) else {
            preconditionFailure("Missing generated contract resource: \(name)")
        }
        return schema
    }
    static func payload(_ name: String) -> JSONValue {
        .object(["$ref":.string("#/$defs/" + name),"$defs":project["$defs"]!])
    }
}
