import Foundation

public enum ProjectDataError: Error, Equatable, Sendable {
    case invalidJSON(String)
    case contract(String)
    case unsupportedVersion(Int)
    case duplicateRegistration(String)
    case missingScenario(UUID)
}

/// Wire-only JSON. Number tokens remain exact, including inside unsupported payloads.
public indirect enum JSONValue: Equatable, Sendable, Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(String), bool(Bool), null

    public init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectDataError.invalidJSON("UTF-8 required")
        }
        var parser = JSONParser(bytes: Array(text.utf8))
        self = try parser.parse()
    }

    public func data() throws -> Data { Data(try text().utf8) }
    public func text() throws -> String {
        switch self {
        case .object(let fields):
            return "{" + (try fields.keys.sorted().map { key in
                try JSONValue.string(key).text() + ":" + fields[key]!.text()
            }).joined(separator: ",") + "}"
        case .array(let items): return "[" + (try items.map { try $0.text() }).joined(separator: ",") + "]"
        case .string(let value): return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        case .number(let token):
            var parser = JSONParser(bytes: Array(token.utf8))
            guard case .number = try parser.parse() else { throw ProjectDataError.invalidJSON("number token") }
            return token
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    public var fields: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var items: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var double: Double? { if case .number(let v) = self { return Double(v) }; return nil }
    public subscript(_ key: String) -> JSONValue? { fields?[key] }

    public init(from decoder: any Decoder) throws {
        if let decoder = decoder as? TreeDecoder { self = decoder.node; return }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .number(try c.decode(Decimal.self).description) }
    }
    public func encode(to encoder: any Encoder) throws {
        if let encoder = encoder as? TreeEncoder { encoder.storage.node = self; return }
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .number:
            // Foundation's encoders cannot retain arbitrary-precision JSON numbers.
            throw ProjectDataError.contract("Use ProjectCodec/JSONTreeCoding for lossless number encoding")
        }
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var index = 0
    mutating func parse() throws -> JSONValue {
        let value = try value(depth: 0)
        skip()
        guard index == bytes.count else { throw error("trailing data") }
        return value
    }
    func error(_ message: String) -> ProjectDataError { .invalidJSON("\(message) at byte \(index)") }
    mutating func skip() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ byte: UInt8) -> Bool {
        skip(); if index < bytes.count && bytes[index] == byte { index += 1; return true }; return false
    }
    mutating func value(depth: Int) throws -> JSONValue {
        guard depth < 128 else { throw error("nesting too deep") }
        skip(); guard index < bytes.count else { throw error("unexpected end") }
        switch bytes[index] {
        case 123:
            index += 1; var fields: [String: JSONValue] = [:]
            if take(125) { return .object(fields) }
            repeat {
                skip(); let key = try string()
                guard fields[key] == nil else { throw error("duplicate_key: \(key)") }
                guard take(58) else { throw error("expected colon") }
                fields[key] = try value(depth: depth + 1)
                if take(125) { return .object(fields) }
            } while take(44)
            throw error("expected object end")
        case 91:
            index += 1; var values: [JSONValue] = []
            if take(93) { return .array(values) }
            repeat {
                values.append(try value(depth: depth + 1))
                if take(93) { return .array(values) }
            } while take(44)
            throw error("expected array end")
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default: return .number(try number())
        }
    }
    mutating func literal(_ text: String) throws {
        let token = Array(text.utf8)
        guard bytes.dropFirst(index).starts(with: token) else { throw error("invalid literal") }
        index += token.count
    }
    mutating func string() throws -> String {
        guard take(34) else { throw error("expected string") }
        let start = index - 1
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if byte == 92 { guard index < bytes.count else { throw error("escape") }; index += 1 }
        }
        throw error("unterminated string")
    }
    mutating func number() throws -> String {
        let start = index
        if index < bytes.count && bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { throw error("number") }
        if bytes[index] == 48 { index += 1 }
        else {
            guard (49...57).contains(bytes[index]) else { throw error("number") }
            digits()
        }
        if index < bytes.count && bytes[index] == 46 {
            index += 1; let before = index; digits(); guard before != index else { throw error("fraction") }
        }
        if index < bytes.count && [69,101].contains(bytes[index]) {
            index += 1
            if index < bytes.count && [43,45].contains(bytes[index]) { index += 1 }
            let before = index; digits(); guard before != index else { throw error("exponent") }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
    mutating func digits() { while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 } }
}
