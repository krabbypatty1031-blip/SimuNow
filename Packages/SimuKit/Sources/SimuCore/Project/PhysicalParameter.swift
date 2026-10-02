import Foundation

public protocol QuantityTag: Sendable { static var unit: String { get } }
public enum LengthTag: QuantityTag { public static let unit = "m" }
public enum AreaTag: QuantityTag { public static let unit = "m2" }
public enum TemperatureTag: QuantityTag { public static let unit = "degC" }
public enum ThermalPowerTag: QuantityTag { public static let unit = "W" }
public enum ElectricalPowerTag: QuantityTag { public static let unit = "W" }
public enum VolumeFlowTag: QuantityTag { public static let unit = "m3/s" }
public enum SpeedTag: QuantityTag { public static let unit = "m/s" }
public enum PressureTag: QuantityTag { public static let unit = "Pa" }
public enum AngleTag: QuantityTag { public static let unit = "deg" }
public enum RatioTag: QuantityTag { public static let unit = "1" }
public enum ActivityTag: QuantityTag { public static let unit = "met" }
public enum ClothingTag: QuantityTag { public static let unit = "clo" }
public enum DensityTag: QuantityTag { public static let unit = "kg/m3" }
public enum UValueTag: QuantityTag { public static let unit = "W/(m2.K)" }
public enum HeatFluxTag: QuantityTag { public static let unit = "W/m2" }
public enum MoneyTag: QuantityTag { public static let unit = "currency" }
public enum EnergyRateTag: QuantityTag { public static let unit = "currency/kWh" }

public struct SourceRecord: Codable, Equatable, Sendable {
    public var kind: ParameterSource
    public var reference: String?
    public var note: String?
    public init(kind: ParameterSource, reference: String? = nil, note: String? = nil) {
        self.kind = kind; self.reference = reference; self.note = note
    }
}
public struct UncertaintyBounds: Codable, Equatable, Sendable {
    public var lower: Double
    public var upper: Double
    public var meaning: String
    public init(lower: Double, upper: Double, meaning: String) {
        self.lower = lower; self.upper = upper; self.meaning = meaning
    }
}

public enum PhysicalParameter<Q: QuantityTag>: Codable, Equatable, Sendable {
    case known(value: Double, source: SourceRecord, uncertainty: UncertaintyBounds? = nil)
    case unknown(reason: String)
    public var value: Double? { if case .known(let v, _, _) = self { return v }; return nil }
    enum Keys: String, CodingKey { case state, value, unit, source, uncertainty, reason }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .state) {
        case "known":
            guard try c.decode(String.self, forKey: .unit) == Q.unit else { throw ProjectDataError.contract("wrong unit: \(Q.unit)") }
            self = .known(value: try c.decode(Double.self, forKey: .value), source: try c.decode(SourceRecord.self, forKey: .source), uncertainty: try c.decodeIfPresent(UncertaintyBounds.self, forKey: .uncertainty))
        case "unknown": self = .unknown(reason: try c.decode(String.self, forKey: .reason))
        default: throw ProjectDataError.contract("unknown parameter state")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .known(let value, let source, let uncertainty):
            guard value.isFinite else { throw ProjectDataError.contract("non_finite") }
            try c.encode("known", forKey: .state); try c.encode(value, forKey: .value)
            try c.encode(Q.unit, forKey: .unit); try c.encode(source, forKey: .source)
            try c.encodeIfPresent(uncertainty, forKey: .uncertainty)
        case .unknown(let reason): try c.encode("unknown", forKey: .state); try c.encode(reason, forKey: .reason)
        }
    }
}
public typealias Length = PhysicalParameter<LengthTag>
public typealias Area = PhysicalParameter<AreaTag>
public typealias Temperature = PhysicalParameter<TemperatureTag>
public typealias ThermalPower = PhysicalParameter<ThermalPowerTag>
public typealias ElectricalPower = PhysicalParameter<ElectricalPowerTag>
public typealias VolumeFlow = PhysicalParameter<VolumeFlowTag>
public typealias Speed = PhysicalParameter<SpeedTag>
public typealias Pressure = PhysicalParameter<PressureTag>
public typealias Angle = PhysicalParameter<AngleTag>
public typealias Ratio = PhysicalParameter<RatioTag>
public typealias Activity = PhysicalParameter<ActivityTag>
public typealias Clothing = PhysicalParameter<ClothingTag>
public typealias Density = PhysicalParameter<DensityTag>
public typealias UValue = PhysicalParameter<UValueTag>
public typealias HeatFlux = PhysicalParameter<HeatFluxTag>
public typealias Money = PhysicalParameter<MoneyTag>
public typealias EnergyRate = PhysicalParameter<EnergyRateTag>
public enum OpeningKind: String, Codable, Sendable { case door, window }
public enum SurfaceFace: String, Codable, Sendable, CaseIterable { case xMin, xMax, yMin, yMax, floor, ceiling }
public enum PortRole: String, Codable, Sendable { case supply, `return` }
public enum Exposure: String, Codable, Sendable { case outdoors, adiabatic }
public enum BoundaryMode: String, Codable, Sendable { case temperature, heatFlux, fromL1 }
