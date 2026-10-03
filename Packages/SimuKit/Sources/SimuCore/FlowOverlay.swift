import Foundation

/// Quality-passed velocity glyphs and streamlines. Values are nearest
/// solve-mesh cell velocities — the same source as seat `uMag` — so display
/// density can never change the physics.
///
/// Wire contract: computation frame (right-handed Z-up metres), metres per
/// second. Glyph length is a display scale in the viewport, not a physical
/// displacement. Streamlines are a steady field, not a cool-down clock.
public struct FlowOverlay: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var quantity: String
    public var unit: String
    public var coordinateSystem: String
    public var sampleMethod: String
    public var streamlineMethod: String
    public var zM: Double
    public var glyphs: [Glyph]
    public var lines: [Streamline]
    public var stats: FlowStats
    public var inputHash: String
    public var quality: String

    public struct Glyph: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double
        public var ux: Double
        public var uy: Double
        public var uz: Double
        public var mag: Double

        public init(x: Double, y: Double, z: Double, ux: Double, uy: Double, uz: Double, mag: Double) {
            self.x = x
            self.y = y
            self.z = z
            self.ux = ux
            self.uy = uy
            self.uz = uz
            self.mag = mag
        }

        public var position: Position3D {
            Position3D(x: x, y: y, z: z)
        }
    }

    public struct StreamlinePoint: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double
        public var mag: Double

        public init(x: Double, y: Double, z: Double, mag: Double) {
            self.x = x
            self.y = y
            self.z = z
            self.mag = mag
        }

        public var position: Position3D {
            Position3D(x: x, y: y, z: z)
        }
    }

    public struct Streamline: Codable, Equatable, Sendable {
        public var id: String
        public var points: [StreamlinePoint]

        public init(id: String, points: [StreamlinePoint]) {
            self.id = id
            self.points = points
        }
    }

    public struct FlowStats: Codable, Equatable, Sendable {
        public var glyphCount: Int
        public var lineCount: Int
        public var minMag: Double?
        public var maxMag: Double?

        public init(glyphCount: Int, lineCount: Int, minMag: Double?, maxMag: Double?) {
            self.glyphCount = glyphCount
            self.lineCount = lineCount
            self.minMag = minMag
            self.maxMag = maxMag
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        quantity = try container.decode(String.self, forKey: .quantity)
        unit = try container.decode(String.self, forKey: .unit)
        coordinateSystem = try container.decode(String.self, forKey: .coordinateSystem)
        sampleMethod = try container.decode(String.self, forKey: .sampleMethod)
        streamlineMethod = try container.decode(String.self, forKey: .streamlineMethod)
        zM = try container.decode(Double.self, forKey: .zM)
        glyphs = try container.decode([Glyph].self, forKey: .glyphs)
        lines = try container.decode([Streamline].self, forKey: .lines)
        stats = try container.decode(FlowStats.self, forKey: .stats)
        inputHash = try container.decode(String.self, forKey: .inputHash)
        quality = try container.decode(String.self, forKey: .quality)
        guard kind == "velocity_overlay", quantity == "air_velocity",
              unit == "m/s", coordinateSystem == "rightHandedZUp",
              sampleMethod == "nearest_cell", streamlineMethod == "rk2_nearest_cell",
              quality == "passed" else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.kind],
                debugDescription: "field-flow wire contract mismatch"
            ))
        }
        guard stats.glyphCount == glyphs.count, stats.lineCount == lines.count else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.stats],
                debugDescription: "flow stats do not match glyph or line counts"
            ))
        }
        for line in lines where line.points.count < 2 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.lines],
                debugDescription: "streamline \(line.id) has fewer than two points"
            ))
        }
    }

    public init(
        schemaVersion: Int = 1,
        kind: String = "velocity_overlay",
        quantity: String = "air_velocity",
        unit: String = "m/s",
        coordinateSystem: String = "rightHandedZUp",
        sampleMethod: String = "nearest_cell",
        streamlineMethod: String = "rk2_nearest_cell",
        zM: Double,
        glyphs: [Glyph],
        lines: [Streamline],
        stats: FlowStats,
        inputHash: String,
        quality: String = "passed"
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.quantity = quantity
        self.unit = unit
        self.coordinateSystem = coordinateSystem
        self.sampleMethod = sampleMethod
        self.streamlineMethod = streamlineMethod
        self.zM = zM
        self.glyphs = glyphs
        self.lines = lines
        self.stats = stats
        self.inputHash = inputHash
        self.quality = quality
    }
}
