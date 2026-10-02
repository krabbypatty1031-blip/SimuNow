import Foundation

/// Codable over the lossless tree, with no Foundation Double conversion of opaque payloads.
public enum JSONTreeCoding {
    public static func decode<T: Decodable>(_ type: T.Type, from node: JSONValue) throws -> T {
        try T(from: TreeDecoder(node: node))
    }
    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = TreeEncoder()
        try value.encode(to: encoder)
        return try encoder.storage.read()
    }
}

struct TreeDecoder: Decoder {
    let node: JSONValue
    var codingPath: [any CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    func container<K: CodingKey>(keyedBy: K.Type) throws -> KeyedDecodingContainer<K> {
        guard let fields = node.fields else { throw ProjectDataError.contract("object required") }
        return KeyedDecodingContainer(TreeKeyedDecoder<K>(fields: fields, codingPath: codingPath))
    }
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard let items = node.items else { throw ProjectDataError.contract("array required") }
        return TreeUnkeyedDecoder(items: items, codingPath: codingPath)
    }
    func singleValueContainer() throws -> any SingleValueDecodingContainer { TreeSingleDecoder(node: node, codingPath: codingPath) }
}
private struct TreeKeyedDecoder<K: CodingKey>: KeyedDecodingContainerProtocol {
    let fields: [String: JSONValue]
    let codingPath: [any CodingKey]
    var allKeys: [K] { fields.keys.compactMap(K.init(stringValue:)) }
    func contains(_ key: K) -> Bool { fields[key.stringValue] != nil }
    func decodeNil(forKey key: K) throws -> Bool { try node(key) == .null }
    func node(_ key: K) throws -> JSONValue {
        guard let v = fields[key.stringValue] else { throw ProjectDataError.contract("missing \(key.stringValue)") }; return v
    }
    func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T { try T(from: TreeDecoder(node: node(key), codingPath: codingPath + [key])) }
    func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: K) throws -> KeyedDecodingContainer<N> { try TreeDecoder(node: node(key)).container(keyedBy: type) }
    func nestedUnkeyedContainer(forKey key: K) throws -> any UnkeyedDecodingContainer { try TreeDecoder(node: node(key)).unkeyedContainer() }
    func superDecoder() throws -> any Decoder { TreeDecoder(node: .object(fields)) }
    func superDecoder(forKey key: K) throws -> any Decoder { TreeDecoder(node: try node(key)) }
}
private struct TreeUnkeyedDecoder: UnkeyedDecodingContainer {
    let items: [JSONValue]
    let codingPath: [any CodingKey]
    var currentIndex = 0
    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex == items.count }
    mutating func next() throws -> JSONValue {
        guard !isAtEnd else { throw ProjectDataError.contract("array end") }
        defer { currentIndex += 1 }; return items[currentIndex]
    }
    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { throw ProjectDataError.contract("array end") }
        if items[currentIndex] == .null { currentIndex += 1; return true }; return false
    }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try T(from: TreeDecoder(node: next())) }
    mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type) throws -> KeyedDecodingContainer<N> { try TreeDecoder(node: next()).container(keyedBy: type) }
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { try TreeDecoder(node: next()).unkeyedContainer() }
    mutating func superDecoder() throws -> any Decoder { TreeDecoder(node: try next()) }
}
private struct TreeSingleDecoder: SingleValueDecodingContainer {
    let node: JSONValue
    let codingPath: [any CodingKey]
    func decodeNil() -> Bool { node == .null }
    func decode(_ type: String.Type) throws -> String {
        guard case .string(let v) = node else { throw ProjectDataError.contract("string required") }; return v
    }
    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let v) = node else { throw ProjectDataError.contract("boolean required") }; return v
    }
    func decode(_ type: Double.Type) throws -> Double {
        guard let v = node.double, v.isFinite else { throw ProjectDataError.contract("finite number required") }; return v
    }
    func decode(_ type: Float.Type) throws -> Float {
        let v = Float(try decode(Double.self)); guard v.isFinite else { throw ProjectDataError.contract("finite float required") }; return v
    }
    func int<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        guard case .number(let token) = node else { throw ProjectDataError.contract("integer required") }
        let parts = token.lowercased().split(separator:"e",omittingEmptySubsequences:false)
        let exponent = parts.count == 2 ? Int(parts[1]) : 0
        guard let exponent, (-10000...10000).contains(exponent) else { throw ProjectDataError.contract("integer out of range") }
        let mantissa = String(parts[0]), negative = mantissa.hasPrefix("-")
        let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
        let decimal = unsigned.split(separator:".",omittingEmptySubsequences:false)
        var digits = decimal.joined()
        let scale = (decimal.count == 2 ? decimal[1].count : 0) - exponent
        if scale > 0 {
            guard digits.suffix(scale).allSatisfy({ $0 == "0" }) else { throw ProjectDataError.contract("integer required") }
            digits = scale >= digits.count ? "0" : String(digits.dropLast(scale))
        } else if scale < 0 {
            guard digits.allSatisfy({ $0 == "0" }) || digits.count - scale <= 20 else { throw ProjectDataError.contract("integer out of range") }
            digits += String(repeating:"0",count:-scale)
        }
        digits = String(digits.drop(while: { $0 == "0" }))
        if digits.isEmpty { digits = "0" }
        guard let result = T((negative ? "-" : "") + digits) else { throw ProjectDataError.contract("integer out of range") }
        return result
    }
    func decode(_ t: Int.Type) throws -> Int { try int(t) }
    func decode(_ t: Int8.Type) throws -> Int8 { try int(t) }
    func decode(_ t: Int16.Type) throws -> Int16 { try int(t) }
    func decode(_ t: Int32.Type) throws -> Int32 { try int(t) }
    func decode(_ t: Int64.Type) throws -> Int64 { try int(t) }
    func decode(_ t: UInt.Type) throws -> UInt { try int(t) }
    func decode(_ t: UInt8.Type) throws -> UInt8 { try int(t) }
    func decode(_ t: UInt16.Type) throws -> UInt16 { try int(t) }
    func decode(_ t: UInt32.Type) throws -> UInt32 { try int(t) }
    func decode(_ t: UInt64.Type) throws -> UInt64 { try int(t) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try T(from: TreeDecoder(node: node, codingPath: codingPath)) }
}

final class TreeStorage {
    var node: JSONValue?
    var object: [String: TreeStorage]?
    var array: [TreeStorage]?
    func read() throws -> JSONValue {
        if let object { return .object(try object.mapValues { try $0.read() }) }
        if let array { return .array(try array.map { try $0.read() }) }
        guard let node else { throw ProjectDataError.contract("empty encoder") }; return node
    }
}
struct TreeEncoder: Encoder {
    let storage: TreeStorage
    var codingPath: [any CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    init(storage: TreeStorage = TreeStorage()) { self.storage = storage }
    func container<K: CodingKey>(keyedBy: K.Type) -> KeyedEncodingContainer<K> {
        storage.object = [:]; return KeyedEncodingContainer(TreeKeyedEncoder<K>(storage: storage, codingPath: codingPath))
    }
    func unkeyedContainer() -> any UnkeyedEncodingContainer { storage.array = []; return TreeUnkeyedEncoder(storage: storage, codingPath: codingPath) }
    func singleValueContainer() -> any SingleValueEncodingContainer { TreeSingleEncoder(storage: storage, codingPath: codingPath) }
}
private struct TreeKeyedEncoder<K: CodingKey>: KeyedEncodingContainerProtocol {
    let storage: TreeStorage
    let codingPath: [any CodingKey]
    func child(_ key: K) -> TreeStorage { let c = TreeStorage(); storage.object?[key.stringValue] = c; return c }
    mutating func encodeNil(forKey key: K) throws { child(key).node = .null }
    mutating func encode<T: Encodable>(_ value: T, forKey key: K) throws { try value.encode(to: TreeEncoder(storage: child(key))) }
    mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: K) -> KeyedEncodingContainer<N> { TreeEncoder(storage: child(key)).container(keyedBy: type) }
    mutating func nestedUnkeyedContainer(forKey key: K) -> any UnkeyedEncodingContainer { TreeEncoder(storage: child(key)).unkeyedContainer() }
    mutating func superEncoder() -> any Encoder { TreeEncoder(storage: storage) }
    mutating func superEncoder(forKey key: K) -> any Encoder { TreeEncoder(storage: child(key)) }
}
private struct TreeUnkeyedEncoder: UnkeyedEncodingContainer {
    let storage: TreeStorage
    let codingPath: [any CodingKey]
    var count: Int { storage.array?.count ?? 0 }
    func child() -> TreeStorage { let c = TreeStorage(); storage.array?.append(c); return c }
    mutating func encodeNil() throws { child().node = .null }
    mutating func encode<T: Encodable>(_ value: T) throws { try value.encode(to: TreeEncoder(storage: child())) }
    mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type) -> KeyedEncodingContainer<N> { TreeEncoder(storage: child()).container(keyedBy: type) }
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer { TreeEncoder(storage: child()).unkeyedContainer() }
    mutating func superEncoder() -> any Encoder { TreeEncoder(storage: child()) }
}
private struct TreeSingleEncoder: SingleValueEncodingContainer {
    let storage: TreeStorage
    let codingPath: [any CodingKey]
    mutating func encodeNil() throws { storage.node = .null }
    mutating func encode(_ value: String) throws { storage.node = .string(value) }
    mutating func encode(_ value: Bool) throws { storage.node = .bool(value) }
    func floating<T: BinaryFloatingPoint>(_ value: T) throws {
        guard value.isFinite else { throw ProjectDataError.contract("non_finite") }
        storage.node = .number(String(describing: value))
    }
    mutating func encode(_ v: Double) throws { try floating(v) }
    mutating func encode(_ v: Float) throws { try floating(v) }
    mutating func encode(_ v: Int) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: Int8) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: Int16) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: Int32) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: Int64) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: UInt) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: UInt8) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: UInt16) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: UInt32) throws { storage.node = .number(String(v)) }
    mutating func encode(_ v: UInt64) throws { storage.node = .number(String(v)) }
    mutating func encode<T: Encodable>(_ value: T) throws { try value.encode(to: TreeEncoder(storage: storage)) }
}
