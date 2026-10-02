import Foundation
import CryptoKit

/// Canonical hash text + SHA-256 for run input identity (Protocols/run-input-v1.md).
/// Rules are shared byte-for-byte with Backend models/hashing.py.
public enum InputHash {
    public static func canonicalText(_ node: JSONValue) throws -> String {
        switch node {
        case .object(let fields):
            let sortedKeys = fields.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            var parts: [String] = []
            for key in sortedKeys {
                parts.append(try escape(key) + ":" + canonicalText(fields[key]!))
            }
            return "{" + parts.joined(separator: ",") + "}"
        case .array(let items):
            let rendered = try items.map { try canonicalText($0) }
            return "[" + rendered.joined(separator: ",") + "]"
        case .string(let value):
            return try escape(value)
        case .number(let token):
            return token
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(of node: JSONValue) throws -> String {
        sha256Hex(try canonicalText(node))
    }

    /// Input hash of an immutable scenario snapshot.
    public static func snapshotHash(_ snapshot: ScenarioInputSnapshot) throws -> String {
        try hash(of: JSONTreeCoding.encode(snapshot))
    }

    private static func escape(_ value: String) throws -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{09}": out += "\\t"
            case "\u{0A}": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\u{0D}": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
