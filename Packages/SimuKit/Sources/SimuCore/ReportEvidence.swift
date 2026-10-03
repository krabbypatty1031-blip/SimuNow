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
    public var dayEnergyKWh: Double?
    public var dayCost: Double?
    public var currency: String?
    public var supplyZ0M: Double?
    public var supplyZ1M: Double?

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
        dayEnergyKWh: Double?,
        dayCost: Double?,
        currency: String?,
        supplyZ0M: Double?,
        supplyZ1M: Double?
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
        self.dayEnergyKWh = dayEnergyKWh
        self.dayCost = dayCost
        self.currency = currency
        self.supplyZ0M = supplyZ0M
        self.supplyZ1M = supplyZ1M
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
    public static func build(from candidates: [CandidateRun]) -> ReportEvidence {
        let runs = candidates.map(EvidenceRun.init(candidate:))
        let reference = candidates.compactMap { $0.draft.costAssumptions?.reference }.first
            ?? "无电价来源"
        return ReportEvidence(
            candidates: runs,
            cards: RecommendationClassifier.cards(from: candidates),
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
        let ratio = candidate.metrics.first { $0.name == "seat_pass_ratio" }
        let seatMin = candidate.metrics.first { $0.name == "seat_t_c_min" }
        self.init(
            name: candidate.name,
            runID: candidate.identity.runID,
            scenarioID: candidate.identity.scenarioID,
            inputHash: candidate.identity.inputHash,
            quality: candidate.quality,
            l1RunID: candidate.l1Identity?.runID,
            seatBandLowC: SeatFeasibility.airLowC,
            seatBandHighC: SeatFeasibility.airHighC,
            seatPassRatio: ratio?.omitted == false ? ratio?.value : nil,
            seatPassRatioOmitted: ratio?.omitted != false,
            seatTMinC: seatMin?.omitted == false ? seatMin?.value : nil,
            dayEnergyKWh: candidate.dayCost.energyOmitted ? nil : candidate.dayCost.energyKWh,
            dayCost: candidate.dayCost.costOmitted ? nil : candidate.dayCost.cost,
            currency: candidate.dayCost.currency,
            supplyZ0M: candidate.draft.hvac?.supply.z0.value,
            supplyZ1M: candidate.draft.hvac?.supply.z1.value
        )
    }
}
