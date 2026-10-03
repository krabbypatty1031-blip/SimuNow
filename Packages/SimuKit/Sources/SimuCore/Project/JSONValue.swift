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
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectDataError.invalidJSON("UTF-8 required")
        }
        var parser = JSONParser(bytes: Array(text.utf8))
        self = try parser.parse()
    }

    /// Emits the same sorted wire bytes as the previous encoder without building a
    /// temporary JSONEncoder and intermediate String for every key/scalar.
    public func data() throws -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(4096)
        try appendJSON(to: &bytes)
        return Data(bytes)
    }
    public func text() throws -> String { String(decoding: try data(), as: UTF8.self) }
    private func appendJSON(to bytes: inout [UInt8]) throws {
        try Task.checkCancellation()
        switch self {
        case .object(let fields):
            bytes.append(123)
            for (index, key) in fields.keys.sorted().enumerated() {
                if index > 0 { bytes.append(44) }
                try Self.appendString(key, to: &bytes)
                bytes.append(58)
                try fields[key]!.appendJSON(to: &bytes)
            }
            bytes.append(125)
        case .array(let items):
            bytes.append(91)
            for (index, item) in items.enumerated() {
                if index > 0 { bytes.append(44) }
                try item.appendJSON(to: &bytes)
            }
            bytes.append(93)
        case .string(let value): try Self.appendString(value, to: &bytes)
        case .number(let token):
            var parser = JSONParser(bytes: Array(token.utf8))
            guard case .number = try parser.parse() else {
                throw ProjectDataError.invalidJSON("number token")
            }
            bytes.append(contentsOf: token.utf8)
        case .bool(let value):
            bytes.append(contentsOf: value ? [116, 114, 117, 101] : [102, 97, 108, 115, 101])
        case .null: bytes.append(contentsOf: [110, 117, 108, 108])
        }
    }
    private static func appendString(_ value: String, to bytes: inout [UInt8]) throws {
        bytes.append(34)
        let hex = Array("0123456789abcdef".utf8)
        for (index, byte) in value.utf8.enumerated() {
            if index & 4095 == 0 { try Task.checkCancellation() }
            switch byte {
            case 34, 47, 92:
                bytes.append(92)
                bytes.append(byte)
            case 8: bytes.append(contentsOf: [92, 98])
            case 9: bytes.append(contentsOf: [92, 116])
            case 10: bytes.append(contentsOf: [92, 110])
            case 12: bytes.append(contentsOf: [92, 102])
            case 13: bytes.append(contentsOf: [92, 114])
            case 0...31:
                bytes.append(contentsOf: [92, 117, 48, 48, hex[Int(byte >> 4)], hex[Int(byte & 15)]])
            default: bytes.append(byte)
            }
        }
        bytes.append(34)
    }

    public var fields: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }
    public var items: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }
    public var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    public var double: Double? {
        if case .number(let v) = self { return Double(v) }
        return nil
    }
    public subscript(_ key: String) -> JSONValue? { fields?[key] }

    public init(from decoder: any Decoder) throws {
        if let decoder = decoder as? TreeDecoder {
            self = decoder.node
            return
        }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else {
            self = .number(try c.decode(Decimal.self).description)
        }
    }
    private func validateNumberTokens() throws {
        try Task.checkCancellation()
        switch self {
        case .number(let token):
            var parser = JSONParser(bytes: Array(token.utf8))
            guard case .number = try parser.parse() else {
                throw ProjectDataError.invalidJSON("number token")
            }
        case .object(let fields): for node in fields.values { try node.validateNumberTokens() }
        case .array(let values): for node in values { try node.validateNumberTokens() }
        default: break
        }
    }
    public func encode(to encoder: any Encoder) throws {
        if let encoder = encoder as? TreeEncoder {
            // Raw/opaque JSON values bypass typed scalar encoders. Keep the same
            // lexical token boundary even when the caller validates without data().
            try validateNumberTokens()
            encoder.storage.node = self
            return
        }
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
    mutating func skip() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    mutating func take(_ byte: UInt8) -> Bool {
        skip()
        if index < bytes.count && bytes[index] == byte {
            index += 1
            return true
        }
        return false
    }
    mutating func value(depth: Int) throws -> JSONValue {
        guard depth < 128 else { throw error("nesting too deep") }
        skip()
        guard index < bytes.count else { throw error("unexpected end") }
        switch bytes[index] {
        case 123:
            index += 1
            var fields: [String: JSONValue] = [:]
            if take(125) { return .object(fields) }
            repeat {
                skip()
                let key = try string()
                guard fields[key] == nil else { throw error("duplicate_key: \(key)") }
                guard take(58) else { throw error("expected colon") }
                fields[key] = try value(depth: depth + 1)
                if take(125) { return .object(fields) }
            } while take(44)
            throw error("expected object end")
        case 91:
            index += 1
            var values: [JSONValue] = []
            if take(93) { return .array(values) }
            repeat {
                values.append(try value(depth: depth + 1))
                if take(93) { return .array(values) }
            } while take(44)
            throw error("expected array end")
        case 34: return .string(try string())
        case 116:
            try literal("true")
            return .bool(true)
        case 102:
            try literal("false")
            return .bool(false)
        case 110:
            try literal("null")
            return .null
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
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                if !escaped { return String(decoding: bytes[(start + 1)..<(index - 1)], as: UTF8.self) }
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            }
            guard byte >= 32 else { throw error("unescaped control") }
            if byte == 92 {
                escaped = true
                guard index < bytes.count else { throw error("escape") }
                index += 1
            }
        }
        throw error("unterminated string")
    }
    mutating func number() throws -> String {
        let start = index
        if index < bytes.count && bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { throw error("number") }
        if bytes[index] == 48 {
            index += 1
        } else {
            guard (49...57).contains(bytes[index]) else { throw error("number") }
            digits()
        }
        if index < bytes.count && bytes[index] == 46 {
            index += 1
            let before = index
            digits()
            guard before != index else { throw error("fraction") }
        }
        if index < bytes.count && [69, 101].contains(bytes[index]) {
            index += 1
            if index < bytes.count && [43, 45].contains(bytes[index]) { index += 1 }
            let before = index
            digits()
            guard before != index else { throw error("exponent") }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
    mutating func digits() { while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 } }
}
