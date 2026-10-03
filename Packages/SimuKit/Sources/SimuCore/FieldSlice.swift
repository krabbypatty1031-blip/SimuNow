import Foundation

/// Seat-height temperature slice from a quality-passed L2 field. Values are
/// nearest solve-mesh cell temperatures - the same source of truth as seat
/// samples - so display density can never change the physics.
///
/// Wire contract: computation frame (right-handed Z-up metres), degrees
/// Celsius, axisOrder ["y", "x"] so `values[j][i]` is row j along y / column i
/// along x. Invalid cells (wall/furniture interiors) display neutral and are
/// excluded from statistics; they are never 0-degree air.
public struct FieldSlice: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var quantity: String
    /// Degrees Celsius on the wire; not display formatting.
    public var unit: String
    public var coordinateSystem: String
    public var axisOrder: [String]
    public var sampleMethod: String
    /// Slice height, metres, computation frame.
    public var zM: Double
    public var originM: SliceOrigin
    public var spacingM: SliceOrigin
    public var shape: SliceShape
    public var values: [[Double]]
    public var valid: [[Bool]]
    public var stats: SliceStats
    /// Input snapshot hash this field belongs to.
    public var inputHash: String
    /// A slice exists only for a quality-passed field; failed fields have none.
    public var quality: String

    public struct SliceOrigin: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct SliceShape: Codable, Equatable, Sendable {
        public var nx: Int
        public var ny: Int

        public init(nx: Int, ny: Int) {
            self.nx = nx
            self.ny = ny
        }
    }

    public struct SliceStats: Codable, Equatable, Sendable {
        public var validCount: Int
        public var minC: Double?
        public var maxC: Double?

        public init(validCount: Int, minC: Double?, maxC: Double?) {
            self.validCount = validCount
            self.minC = minC
            self.maxC = maxC
        }
    }

    /// Decoding is strict about the wire claims the plan pins: unit, frame,
    /// axis order and sample method. A payload that changes any of them is a
    /// different contract, not a display detail.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        quantity = try container.decode(String.self, forKey: .quantity)
        unit = try container.decode(String.self, forKey: .unit)
        coordinateSystem = try container.decode(String.self, forKey: .coordinateSystem)
        axisOrder = try container.decode([String].self, forKey: .axisOrder)
        sampleMethod = try container.decode(String.self, forKey: .sampleMethod)
        zM = try container.decode(Double.self, forKey: .zM)
        originM = try container.decode(SliceOrigin.self, forKey: .originM)
        spacingM = try container.decode(SliceOrigin.self, forKey: .spacingM)
        shape = try container.decode(SliceShape.self, forKey: .shape)
        values = try container.decode([[Double]].self, forKey: .values)
        valid = try container.decode([[Bool]].self, forKey: .valid)
        stats = try container.decode(SliceStats.self, forKey: .stats)
        inputHash = try container.decode(String.self, forKey: .inputHash)
        quality = try container.decode(String.self, forKey: .quality)
        guard kind == "temperature_slice", quantity == "air_temperature",
              unit == "C", coordinateSystem == "rightHandedZUp",
              axisOrder == ["y", "x"], sampleMethod == "nearest_cell",
              quality == "passed" else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.kind],
                debugDescription: "field-slice wire contract mismatch"
            ))
        }
        guard values.count == shape.ny, valid.count == shape.ny else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.shape],
                debugDescription: "slice rows do not match shape.ny"
            ))
        }
        for row in values {
            guard row.count == shape.nx else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [CodingKeys.shape],
                    debugDescription: "slice row length does not match shape.nx"
                ))
            }
        }
    }

    public init(
        schemaVersion: Int = 1,
        kind: String = "temperature_slice",
        quantity: String = "air_temperature",
        unit: String = "C",
        coordinateSystem: String = "rightHandedZUp",
        axisOrder: [String] = ["y", "x"],
        sampleMethod: String = "nearest_cell",
        zM: Double,
        originM: SliceOrigin,
        spacingM: SliceOrigin,
        shape: SliceShape,
        values: [[Double]],
        valid: [[Bool]],
        stats: SliceStats,
        inputHash: String,
        quality: String = "passed"
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.quantity = quantity
        self.unit = unit
        self.coordinateSystem = coordinateSystem
        self.axisOrder = axisOrder
        self.sampleMethod = sampleMethod
        self.zM = zM
        self.originM = originM
        self.spacingM = spacingM
        self.shape = shape
        self.values = values
        self.valid = valid
        self.stats = stats
        self.inputHash = inputHash
        self.quality = quality
    }
}
