import Foundation

/// One comfort input copied off the pinned draft. Missing keys stay nil
/// rather than a neutral stand-in.
public struct EvidenceAssumption: Codable, Equatable, Sendable {
    public var name: String
    public var value: Double?
    public var unit: String
    public var reference: String?

    public init(name: String, value: Double?, unit: String, reference: String? = nil) {
        self.name = name
        self.value = value
        self.unit = unit
        self.reference = reference
    }
}

/// Numbers for one pinned run. Copied at build time; later draft edits do not rewrite them.
public struct EvidenceRun: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { runID }
    public var name: String
    public var runID: UUID
    public var scenarioID: UUID
    public var inputHash: String
    public var quality: QualityState
    public var l1RunID: UUID?
    /// Demo seat-temperature gate copied from `SeatFeasibility`, not a measured sample.
    public var seatBandLowC: Double
    public var seatBandHighC: Double
    public var seatPassRatio: Double?
    public var seatPassRatioOmitted: Bool
    public var seatTMinC: Double?
    public var seatTMaxC: Double?
    public var dayEnergyKWh: Double?
    public var dayCost: Double?
    public var currency: String?
    public var supplyZ0M: Double?
    public var supplyZ1M: Double?
    public var windowCount: Int?
    public var windowAreaM2: Double?
    public var roomLengthM: Double?
    public var roomWidthM: Double?
    public var roomHeightM: Double?
    public var occupantCount: Double?
    public var setpointC: Double?
    public var supplyTemperatureC: Double?
    public var cop: Double?
    public var coolingW: Double?
    public var electricPowerW: Double?
    public var occupiedHours: Double?
    public var occupiedDaysPerYear: Double?
    public var indoorMeanC: Double?
    public var indoorMinC: Double?
    public var indoorMaxC: Double?
    public var sliceZM: Double?
    public var flowMinMps: Double?
    public var flowMaxMps: Double?
    public var seatSpeedMaxMps: Double?
    public var annualEnergyKWh: Double?
    public var annualCost: Double?
    public var pricePerKWh: Double?

    public init(
        name: String,
        runID: UUID,
        scenarioID: UUID,
        inputHash: String,
        quality: QualityState,
        l1RunID: UUID? = nil,
        seatBandLowC: Double,
        seatBandHighC: Double,
        seatPassRatio: Double?,
        seatPassRatioOmitted: Bool,
        seatTMinC: Double? = nil,
        seatTMaxC: Double? = nil,
        dayEnergyKWh: Double?,
        dayCost: Double?,
        currency: String?,
        supplyZ0M: Double?,
        supplyZ1M: Double?,
        windowCount: Int? = nil,
        windowAreaM2: Double? = nil,
        roomLengthM: Double? = nil,
        roomWidthM: Double? = nil,
        roomHeightM: Double? = nil,
        occupantCount: Double? = nil,
        setpointC: Double? = nil,
        supplyTemperatureC: Double? = nil,
        cop: Double? = nil,
        coolingW: Double? = nil,
        electricPowerW: Double? = nil,
        occupiedHours: Double? = nil,
        occupiedDaysPerYear: Double? = nil,
        indoorMeanC: Double? = nil,
        indoorMinC: Double? = nil,
        indoorMaxC: Double? = nil,
        sliceZM: Double? = nil,
        flowMinMps: Double? = nil,
        flowMaxMps: Double? = nil,
        seatSpeedMaxMps: Double? = nil,
        annualEnergyKWh: Double? = nil,
        annualCost: Double? = nil,
        pricePerKWh: Double? = nil
    ) {
        self.name = name
        self.runID = runID
        self.scenarioID = scenarioID
        self.inputHash = inputHash
        self.quality = quality
        self.l1RunID = l1RunID
        self.seatBandLowC = seatBandLowC
        self.seatBandHighC = seatBandHighC
        self.seatPassRatio = seatPassRatio
        self.seatPassRatioOmitted = seatPassRatioOmitted
        self.seatTMinC = seatTMinC
        self.seatTMaxC = seatTMaxC
        self.dayEnergyKWh = dayEnergyKWh
        self.dayCost = dayCost
        self.currency = currency
        self.supplyZ0M = supplyZ0M
        self.supplyZ1M = supplyZ1M
        self.windowCount = windowCount
        self.windowAreaM2 = windowAreaM2
        self.roomLengthM = roomLengthM
        self.roomWidthM = roomWidthM
        self.roomHeightM = roomHeightM
        self.occupantCount = occupantCount
        self.setpointC = setpointC
        self.supplyTemperatureC = supplyTemperatureC
        self.cop = cop
        self.coolingW = coolingW
        self.electricPowerW = electricPowerW
        self.occupiedHours = occupiedHours
        self.occupiedDaysPerYear = occupiedDaysPerYear
        self.indoorMeanC = indoorMeanC
        self.indoorMinC = indoorMinC
        self.indoorMaxC = indoorMaxC
        self.sliceZM = sliceZM
        self.flowMinMps = flowMinMps
        self.flowMaxMps = flowMaxMps
        self.seatSpeedMaxMps = seatSpeedMaxMps
        self.annualEnergyKWh = annualEnergyKWh
        self.annualCost = annualCost
        self.pricePerKWh = pricePerKWh
    }
}

/// Immutable report source. Tables may print only these fields.
public struct ReportEvidence: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var candidates: [EvidenceRun]
    public var cards: [RecommendationCard]
    public var tariffReference: String
    public var comfortAssumptions: [EvidenceAssumption]

    public init(
        schemaVersion: Int = 1,
        candidates: [EvidenceRun],
        cards: [RecommendationCard],
        tariffReference: String,
        comfortAssumptions: [EvidenceAssumption]
    ) {
        self.schemaVersion = schemaVersion
        self.candidates = candidates
        self.cards = cards
        self.tariffReference = tariffReference
        self.comfortAssumptions = comfortAssumptions
    }

    /// Explanation-only packs stay on the report page; they are not a recommendation PDF.
    public var containsExportableRecommendation: Bool {
        cards.contains { $0.kind != .explanation && $0.qualityPassed }
    }

    /// L2 identities plus any L1 identities the cards cite. Built from this object, not the live draft.
    public var citedRunIDs: [UUID] {
        var ids = candidates.map(\.runID)
        for card in cards {
            for id in card.citedRunIDs where !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    /// Snapshot pinned candidates. Metrics and hashes are copied; nothing is recomputed from a view.
    public static func build(
        from candidates: [CandidateRun],
        copy: UserFacingCopy = .english
    ) -> ReportEvidence {
        let runs = candidates.map(EvidenceRun.init(candidate:))
        let reference = candidates.compactMap { $0.draft.costAssumptions?.reference }.first
            ?? copy.noReference
        return ReportEvidence(
            candidates: runs,
            cards: RecommendationClassifier.cards(from: candidates, copy: copy),
            tariffReference: reference,
            comfortAssumptions: comfortAssumptions(from: candidates)
        )
    }

    private static func comfortAssumptions(from candidates: [CandidateRun]) -> [EvidenceAssumption] {
        guard let comfort = candidates.compactMap({ $0.draft.occupancy?.comfort }).first else {
            return []
        }
        return [
            EvidenceAssumption(name: "mrtC", value: comfort.mrtC.value, unit: comfort.mrtC.unit, reference: comfort.mrtC.reference),
            EvidenceAssumption(name: "rhPct", value: comfort.rhPct.value, unit: comfort.rhPct.unit, reference: comfort.rhPct.reference),
            EvidenceAssumption(name: "clo", value: comfort.clo.value, unit: comfort.clo.unit, reference: comfort.clo.reference),
            EvidenceAssumption(name: "met", value: comfort.met.value, unit: comfort.met.unit, reference: comfort.met.reference),
        ]
    }
}

extension EvidenceRun {
    init(candidate: CandidateRun) {
        let windows = (candidate.draft.geometry?.openings ?? []).filter { $0.kind == .window }
        let windowArea = windows.isEmpty ? nil : windows.reduce(0.0) { $0 + $1.patchAreaM2 }
        let electric = candidate.dayCost.electricPowerW ?? Self.metric(candidate, "p_elec_w")
        let cop = candidate.draft.hvac?.cop.value
        let cooling: Double?
        if let listed = Self.metric(candidate, "q_cool_w") {
            cooling = listed
        } else if let electric, let cop, cop > 0 {
            cooling = electric * cop
        } else {
            cooling = nil
        }
        let dayEnergy = candidate.dayCost.energyOmitted ? nil : candidate.dayCost.energyKWh
        let dayCost = candidate.dayCost.costOmitted ? nil : candidate.dayCost.cost
        self.init(
            name: candidate.name,
            runID: candidate.identity.runID,
            scenarioID: candidate.identity.scenarioID,
            inputHash: candidate.identity.inputHash,
            quality: candidate.quality,
            l1RunID: candidate.l1Identity?.runID,
            seatBandLowC: SeatFeasibility.airLowC,
            seatBandHighC: SeatFeasibility.airHighC,
            seatPassRatio: Self.metric(candidate, "seat_pass_ratio"),
            seatPassRatioOmitted: Self.metric(candidate, "seat_pass_ratio") == nil,
            seatTMinC: Self.metric(candidate, "seat_t_c_min"),
            seatTMaxC: Self.metric(candidate, "seat_t_c_max"),
            dayEnergyKWh: dayEnergy,
            dayCost: dayCost,
            currency: candidate.dayCost.currency,
            supplyZ0M: candidate.draft.hvac?.supply.z0.value,
            supplyZ1M: candidate.draft.hvac?.supply.z1.value,
            windowCount: windows.count,
            windowAreaM2: windowArea,
            roomLengthM: candidate.draft.geometry?.sizeX.value,
            roomWidthM: candidate.draft.geometry?.sizeY.value,
            roomHeightM: candidate.draft.geometry?.sizeZ.value,
            occupantCount: candidate.basis.occupantCount,
            setpointC: candidate.basis.setpointC,
            supplyTemperatureC: candidate.basis.supplyTemperatureC,
            cop: cop,
            coolingW: cooling,
            electricPowerW: electric,
            occupiedHours: candidate.dayCost.occupiedHours,
            occupiedDaysPerYear: CostAccounting.occupiedDaysPerYear,
            indoorMeanC: candidate.slice?.meanValidC,
            indoorMinC: candidate.slice?.stats.minC,
            indoorMaxC: candidate.slice?.stats.maxC,
            sliceZM: candidate.slice?.zM,
            flowMinMps: candidate.flow?.stats.minMag,
            flowMaxMps: candidate.flow?.stats.maxMag,
            seatSpeedMaxMps: Self.metric(candidate, "seat_u_mag_max"),
            annualEnergyKWh: CostAccounting.annualEnergyKWh(from: dayEnergy),
            annualCost: CostAccounting.annualCost(from: dayCost),
            pricePerKWh: candidate.dayCost.pricePerKWh
        )
    }

    private static func metric(_ candidate: CandidateRun, _ name: String) -> Double? {
        guard let row = candidate.metrics.first(where: { $0.name == name }), !row.omitted else {
            return nil
        }
        return row.value
    }
}
