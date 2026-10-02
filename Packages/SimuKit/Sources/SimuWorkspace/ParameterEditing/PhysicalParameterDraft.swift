import Foundation
import SimuCore

/// Text remains separate from the wire model until the user explicitly applies the form.
public struct PhysicalParameterDraft: Equatable, Sendable {
    public var isKnown: Bool
    public var valueText: String
    public var unknownReason: String
    public var sourceKind: ParameterSource
    public var reference: String
    public var note: String
    public var hasUncertainty: Bool
    public var lowerText: String
    public var upperText: String
    public var uncertaintyMeaning: String

    public init<Q: QuantityTag>(_ parameter: PhysicalParameter<Q>) {
        isKnown = false; valueText = ""; unknownReason = ""; sourceKind = .user
        reference = ""; note = ""; hasUncertainty = false
        lowerText = ""; upperText = ""; uncertaintyMeaning = ""
        switch parameter {
        case .unknown(let reason): unknownReason = reason
        case .known(let value, let source, let uncertainty):
            isKnown = true; valueText = Self.format(value); sourceKind = source.kind
            reference = source.reference ?? ""; note = source.note ?? ""
            if let uncertainty {
                hasUncertainty = true; lowerText = Self.format(uncertainty.lower)
                upperText = Self.format(uncertainty.upper); uncertaintyMeaning = uncertainty.meaning
            }
        }
    }

    public init(unknownReason: String = "尚未录入") {
        self.init(Length.unknown(reason: unknownReason))
    }

    /// A changed value no longer claims the old measurement or manufacturer provenance.
    public mutating func enterValue(_ text: String) {
        guard valueText != text else { return }
        let previous = try? Self.number(valueText)
        let next = try? Self.number(text)
        valueText = text
        if previous == nil || next == nil || previous != next {
            sourceKind = .user; reference = ""; note = ""
            hasUncertainty = false
        }
    }

    public func parameter<Q: QuantityTag>(as type: Q.Type = Q.self,
                                          range: ParameterValueRange = .unbounded) throws -> PhysicalParameter<Q> {
        if !isKnown {
            guard let reason = Self.nonempty(unknownReason) else { throw ParameterDraftError.unknownReason }
            return .unknown(reason: reason)
        }
        let value = try Self.number(valueText)
        guard range.contains(value) else { throw ParameterDraftError.range(range.description) }
        let source = SourceRecord(kind: sourceKind, reference: Self.nonempty(reference), note: Self.nonempty(note))
        if [.manufacturer, .measured, .preset].contains(sourceKind), source.reference == nil {
            throw ParameterDraftError.sourceReference
        }
        if sourceKind == .assumed, source.note == nil { throw ParameterDraftError.assumptionNote }
        var uncertainty: UncertaintyBounds?
        if hasUncertainty {
            let lower = try Self.number(lowerText), upper = try Self.number(upperText)
            guard lower <= value, value <= upper, let meaning = Self.nonempty(uncertaintyMeaning) else {
                throw ParameterDraftError.uncertainty
            }
            uncertainty = .init(lower: lower, upper: upper, meaning: meaning)
        }
        return .known(value: value, source: source, uncertainty: uncertainty)
    }

    public static func number(_ text: String) throws -> Double {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let value = Double(text), value.isFinite else { throw ParameterDraftError.number }
        return value
    }
    private static func format(_ value: Double) -> String { String(value) }
    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ParameterValueRange: Equatable, Sendable {
    public var minimum: Double?
    public var maximum: Double?
    public var minimumInclusive: Bool
    public var maximumInclusive: Bool
    public init(minimum: Double? = nil, maximum: Double? = nil,
                minimumInclusive: Bool = true, maximumInclusive: Bool = true) {
        self.minimum = minimum; self.maximum = maximum
        self.minimumInclusive = minimumInclusive; self.maximumInclusive = maximumInclusive
    }
    public static let unbounded = Self()
    public static let nonnegative = Self(minimum: 0)
    public static let positive = Self(minimum: 0, minimumInclusive: false)
    public static let fraction = Self(minimum: 0, maximum: 1)
    public static let northBearing = Self(minimum: 0, maximum: 360, maximumInclusive: false)
    public func contains(_ value: Double) -> Bool {
        value.isFinite && (minimum.map { minimumInclusive ? value >= $0 : value > $0 } ?? true)
        && (maximum.map { maximumInclusive ? value <= $0 : value < $0 } ?? true)
    }
    public var description: String {
        if let minimum, let maximum { return "\(minimumInclusive ? "≥" : ">") \(minimum)，\(maximumInclusive ? "≤" : "<") \(maximum)" }
        if let minimum { return "\(minimumInclusive ? "≥" : ">") \(minimum)" }
        if let maximum { return "\(maximumInclusive ? "≤" : "<") \(maximum)" }
        return "有限数值"
    }
}

public enum ParameterDraftError: LocalizedError, Equatable {
    case number, unknownReason, sourceReference, assumptionNote, uncertainty
    case range(String)
    public var errorDescription: String? {
        switch self {
        case .number: "请输入完整的有限数值；小数使用小数点。"
        case .unknownReason: "请说明此参数为何未知。"
        case .sourceReference: "实测、厂家或预设参数需要填写来源依据。"
        case .assumptionNote: "请说明此假设的内容和理由。"
        case .uncertainty: "上下界应包含当前值，并说明上下界的含义。"
        case .range(let range): "参数范围：\(range)。"
        }
    }
}
