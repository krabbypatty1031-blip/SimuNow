import Foundation

/// One pinned scenario result for side-by-side comparison. Pinned from a
/// finished, current run; the record is a frozen copy that never re-derives
/// metrics and never fabricates a slice. Geometry is the comparison axis -
/// the non-geometry basis must match across candidates or they are not a
/// valid comparison.
public struct CandidateRun: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { identity.runID }
    public var name: String
    public var identity: RunIdentity
    public var state: RunState
    public var quality: QualityState
    public var metrics: [ResultMetric]
    /// Seat-height slice from the pinned run; absent when quality failed.
    public var slice: FieldSlice?
    /// Steady flow overlay from the same pinned run; absent when quality failed.
    public var flow: FlowOverlay?
    /// Per-seat L2 samples frozen at pin time so the comparison viewport can
    /// label each seat with its measured air temperature. Absent (also for
    /// records decoded from older packages) when the pinned run had none;
    /// seats then show only their names, never a fabricated number.
    public var seatSamples: [SeatSample]?
    /// Frozen run-time basis (people, hours, setpoints, supply temperature).
    public var basis: ComparisonBasis
    /// Geometry snapshot at pin time; the comparison viewport draws this,
    /// never the live draft the user may still be editing.
    public var draft: ProjectDraft
    /// L1 electric power and representative-day cost frozen at pin time.
    /// Absent L1 leaves the cost omitted, never 0.
    public var dayCost: RepresentativeDayCost
    /// L1 identity frozen at pin time. Separate from `identity`, which is the
    /// pinned run (current L2 when one exists). The comparison card uses this
    /// hash so stale L1 watts are not labelled as the current draft.
    public var l1Identity: RunIdentity?

    public init(
        name: String,
        identity: RunIdentity,
        state: RunState,
        quality: QualityState,
        metrics: [ResultMetric],
        slice: FieldSlice? = nil,
        flow: FlowOverlay? = nil,
        seatSamples: [SeatSample]? = nil,
        basis: ComparisonBasis,
        draft: ProjectDraft,
        dayCost: RepresentativeDayCost = .omitted(reason: "无 L1，代表日电费省略"),
        l1Identity: RunIdentity? = nil
    ) {
        self.name = name
        self.identity = identity
        self.state = state
        self.quality = quality
        self.metrics = metrics
        self.slice = slice
        self.flow = flow
        self.seatSamples = seatSamples
        self.basis = basis
        self.draft = draft
        self.dayCost = dayCost
        self.l1Identity = l1Identity
    }

    /// Non-geometry inputs that must match before two candidates may be
    /// compared side by side. The typical-year calendar day is part of the
    /// weather basis; different days cannot be compared as the same day.
    public struct ComparisonBasis: Codable, Equatable, Sendable {
        public var occupantCount: Double
        public var occupiedStart: String
        public var occupiedEnd: String
        public var setpointC: Double
        public var supplyTemperatureC: Double
        /// Typical-year month. Old pins without the field decode as July.
        public var weatherMonth: Int
        /// Typical-year day. Old pins without the field decode as the 15th.
        public var weatherDay: Int

        public init(
            occupantCount: Double,
            occupiedStart: String,
            occupiedEnd: String,
            setpointC: Double,
            supplyTemperatureC: Double,
            weatherMonth: Int = 7,
            weatherDay: Int = 15
        ) {
            self.occupantCount = occupantCount
            self.occupiedStart = occupiedStart
            self.occupiedEnd = occupiedEnd
            self.setpointC = setpointC
            self.supplyTemperatureC = supplyTemperatureC
            self.weatherMonth = weatherMonth
            self.weatherDay = weatherDay
        }

        enum CodingKeys: String, CodingKey {
            case occupantCount, occupiedStart, occupiedEnd, setpointC, supplyTemperatureC
            case weatherMonth, weatherDay
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            occupantCount = try container.decode(Double.self, forKey: .occupantCount)
            occupiedStart = try container.decode(String.self, forKey: .occupiedStart)
            occupiedEnd = try container.decode(String.self, forKey: .occupiedEnd)
            setpointC = try container.decode(Double.self, forKey: .setpointC)
            supplyTemperatureC = try container.decode(Double.self, forKey: .supplyTemperatureC)
            weatherMonth = try container.decodeIfPresent(Int.self, forKey: .weatherMonth) ?? 7
            weatherDay = try container.decodeIfPresent(Int.self, forKey: .weatherDay) ?? 15
        }
    }

    /// nil when the two bases match; otherwise a reason naming the
    /// mismatched fields. Different bases cannot be shown as a valid
    /// comparison, and the UI must say so instead of hiding the difference.
    public static func basisMismatch(
        _ a: ComparisonBasis,
        _ b: ComparisonBasis,
        copy: UserFacingCopy = .english
    ) -> String? {
        var mismatches: [String] = []
        if a.occupantCount != b.occupantCount {
            mismatches.append(copy.mismatchOccupants)
        }
        if a.occupiedStart != b.occupiedStart || a.occupiedEnd != b.occupiedEnd {
            mismatches.append(copy.mismatchHours)
        }
        if a.setpointC != b.setpointC {
            mismatches.append(copy.mismatchSetpoint)
        }
        if a.supplyTemperatureC != b.supplyTemperatureC {
            mismatches.append(copy.mismatchSupply)
        }
        if a.weatherMonth != b.weatherMonth || a.weatherDay != b.weatherDay {
            mismatches.append(copy.mismatchWeatherDay)
        }
        guard !mismatches.isEmpty else { return nil }
        return copy.basisMismatch(mismatches)
    }
}
