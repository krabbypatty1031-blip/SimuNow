import Foundation
import SimuCore

public indirect enum NativeCanonicalValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case string(String)
    case integer(Int64)
    case unsigned(UInt64)
    case double(Double)
    case opaqueNumber(String)
    case array([NativeCanonicalValue])
    case object([String: NativeCanonicalValue])
}
public enum AnalysisCanonicalizer {
    public static let format = "simunow.native.canonical.v1"
    /// Type tags: n=0,t=1,f=2,s=3,i=4,u=5,d=6,o=7,a=8,m=9.
    public static func bytes(_ value: NativeCanonicalValue) throws -> Data {
        var data = Data()
        try append(value, to: &data)
        return data
    }
    private static func count(_ n: UInt64, to data: inout Data) {
        var n = n.bigEndian
        withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
    }
    private static func text(_ string: String, to data: inout Data) {
        let bytes = Data(string.utf8)
        count(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }
    private static func append(_ v: NativeCanonicalValue, to data: inout Data) throws {
        try Task.checkCancellation()
        switch v {
        case .null: data.append(0)
        case .bool(let b): data.append(b ? 1 : 2)
        case .string(let s):
            data.append(3)
            text(s, to: &data)
        case .integer(let i):
            data.append(4)
            count(UInt64(bitPattern: i), to: &data)
        case .unsigned(let i):
            data.append(5)
            count(i, to: &data)
        case .double(let d):
            guard d.isFinite else { throw ProjectDataError.contract("canonical nonfinite") }
            data.append(6)
            count((d == 0 ? 0.0 : d).bitPattern, to: &data)
        case .opaqueNumber(let token):
            guard case .number = try JSONValue(data: Data(token.utf8)) else {
                throw ProjectDataError.contract("canonical opaque token")
            }
            data.append(7)
            text(token, to: &data)
        case .array(let items):
            data.append(8)
            count(UInt64(items.count), to: &data)
            for item in items { try append(item, to: &data) }
        case .object(let fields):
            data.append(9)
            count(UInt64(fields.count), to: &data)
            for key in fields.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                text(key, to: &data)
                try append(fields[key]!, to: &data)
            }
        }
    }
    /// Schema-guided typed numbers, plus original opaque tokens for unsupported extensions.
    public static func value(
        _ node: JSONValue, schema: JSONValue?, root: JSONValue,
        registry: ModelRegistry = .builtIn, path: String = ""
    ) throws -> NativeCanonicalValue {
        try Task.checkCancellation()
        var schema = schema
        while let ref = schema?["$ref"]?.string, ref.hasPrefix("#/$defs/") {
            schema = root["$defs"]?[String(ref.dropFirst(8))]
        }
        if let choices = schema?["anyOf"]?.items {
            schema = choices.first { choice in
                var wrapper = choice.fields ?? [:]
                wrapper["$defs"] = root["$defs"]
                return (try? WireSchema.validate(node, schema: .object(wrapper))) != nil
            }
            return try value(node, schema: schema, root: root, registry: registry, path: path)
        }
        switch node {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .string(let s): return .string(schema?["format"]?.string == "uuid" ? s.lowercased() : s)
        case .number(let token):
            if schema?["type"]?.string == "integer" {
                // Integer DTO tokens take the direct exact path; decimal/exponent
                // spellings retain the original lossless decoder's normalization.
                if let i = Int64(token) { return .integer(i) }
                if let u = UInt64(token) { return .unsigned(u) }
                if let i = try? JSONTreeCoding.decode(Int64.self, from: node) { return .integer(i) }
                return .unsigned(try JSONTreeCoding.decode(UInt64.self, from: node))
            }
            if schema?["type"]?.string == "number" {
                guard let value = Double(token), value.isFinite else {
                    throw ProjectDataError.contract("finite number required")
                }
                return .double(value)
            }
            return .opaqueNumber(token)
        case .array(let items):
            return .array(
                try items.enumerated().map {
                    try value(
                        $0.element, schema: schema?["items"], root: root, registry: registry,
                        path: path + "/\($0.offset)")
                })
        case .object(let fields):
            var out: [String: NativeCanonicalValue] = [:]
            for (key, child) in fields {
                if key == "payload", let kind = fields["kind"]?.string,
                    let version = fields["payloadVersion"]?.double,
                    let registration = registry.registrations.first(where: {
                        $0.kind == kind && Double($0.version) == version
                    })
                {
                    out[key] = try value(
                        child, schema: registration.schema, root: registration.schema, registry: registry,
                        path: path + "/payload")
                } else {
                    out[key] = try value(
                        child, schema: schema?["properties"]?[key], root: root, registry: registry,
                        path: path + "/" + key)
                }
            }
            return .object(out)
        }
    }
}
