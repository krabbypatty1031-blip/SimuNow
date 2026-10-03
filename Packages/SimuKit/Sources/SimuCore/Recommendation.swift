import Foundation

/// Which claim a card is allowed to make. Code assigns the kind; a narrator
/// may only attach prose later and must not invent a fourth score.
public enum RecommendationKind: String, Codable, Sendable, Equatable {
    /// Capacity, quality, or basis limit. Not a named scheme.
    case explanation
    /// Same-basis setpoint, flow, or occupancy lever, with an L1 cost delta or an explicit tie.
    case operation
    /// Same-basis geometry change that moved seat temperature or the model pass ratio.
    case comfort
    /// Equipment or installation. No quote means 待报价 and no payback.
    case retrofit

    /// Short label for the report page. The three recommendation kinds stay distinct.
    public func label(_ copy: UserFacingCopy = .english) -> String {
        copy.recommendationKindLabel(self)
    }
}

/// One structured recommendation. Numbers in `detail` are copied from pinned runs.
/// `payback` stays nil unless a real quote exists; this phase never has one.
public struct RecommendationCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: RecommendationKind
    public var title: String
    public var detail: String
    public var citedRunIDs: [UUID]
    public var qualityPassed: Bool
    public var assumptions: [String]
    /// 「待报价」 when the card is a retrofit without a vendor quote.
    public var quoteStatus: String?
    /// Absent when there is no quote to recover. Never a computed year count.
    public var payback: String?

    public init(
        id: String,
        kind: RecommendationKind,
        title: String,
        detail: String,
        citedRunIDs: [UUID],
        qualityPassed: Bool,
        assumptions: [String] = [],
        quoteStatus: String? = nil,
        payback: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.citedRunIDs = citedRunIDs
        self.qualityPassed = qualityPassed
        self.assumptions = assumptions
        self.quoteStatus = quoteStatus
        self.payback = payback
    }

    /// First sentence for the unfolded report card. The rest stays behind disclosure.
    public var summary: String {
        if let end = detail.firstIndex(of: "。") {
            return String(detail[...end])
        }
        if let range = detail.range(of: ". ") {
            return String(detail[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return detail
    }
}

/// Classifies pinned candidates into cards. Does not resimulate and does not
/// blend objectives into one score.
public enum RecommendationClassifier: Sendable {
    public static func cards(
        from candidates: [CandidateRun],
        copy: UserFacingCopy = .english
    ) -> [RecommendationCard] {
        guard !candidates.isEmpty else { return [] }
        if !candidates.contains(where: isQualityPassedField) {
            return [explanation(
                id: "no-quality-passed-field",
                title: copy.recommendCannotCompareTitle,
                detail: copy.recommendCannotCompareDetail,
                candidates: candidates
            )]
        }
        if allEvaluatedSeatsFail(candidates) {
            return [explanation(
                id: "no-feasible-seats",
                title: copy.recommendNoFeasibleTitle,
                detail: copy.recommendNoFeasibleDetail,
                candidates: candidates.filter(isQualityPassedField)
            )]
        }

        let fields = candidates.filter(isQualityPassedField)
        // A mixed basis is not a quieter comparison: it cannot become a recommendation PDF.
        if let reason = mixedBasisReason(fields, copy: copy) {
            return [explanation(
                id: "basis-mismatch",
                title: copy.recommendBasisMismatchTitle,
                detail: copy.recommendBasisMismatchDetail(reason),
                candidates: fields
            )]
        }

        let comparable = sameBasis(asLeadOf: fields)
        var cards: [RecommendationCard] = []
        if let constraint = constraintCard(comparable, copy: copy) {
            cards.append(constraint)
        }
        if let comfort = comfortCard(comparable, copy: copy) {
            cards.append(comfort)
        }
        if let operation = operationCard(comparable, copy: copy) {
            cards.append(operation)
        }
        if let retrofit = retrofitCard(comparable, copy: copy) {
            cards.append(retrofit)
        }
        return cards
    }

    /// Quality passed and a non-omitted pass ratio. A failed solve is not a field.
    private static func isQualityPassedField(_ candidate: CandidateRun) -> Bool {
        guard candidate.quality == .passed,
              let ratio = metric(candidate, "seat_pass_ratio"),
              !ratio.omitted,
              ratio.value != nil else {
            return false
        }
        return true
    }

    /// eval_count > 0 and pass_count = 0 on every quality-passed field.
    private static func allEvaluatedSeatsFail(_ candidates: [CandidateRun]) -> Bool {
        let fields = candidates.filter(isQualityPassedField)
        guard !fields.isEmpty else { return false }
        return fields.allSatisfy { candidate in
            guard let evalCount = number(candidate, "seat_eval_count"),
                  let passCount = number(candidate, "seat_pass_count") else {
                return false
            }
            return evalCount > 0 && passCount == 0
        }
    }

    /// True only when a card is a quality-passed recommendation, not an explanation.
    public static func canExportRecommendation(from candidates: [CandidateRun]) -> Bool {
        cards(from: candidates).contains { $0.kind != .explanation && $0.qualityPassed }
    }

    /// Any occupancy, hours, or temperature mismatch versus the lead field.
    private static func mixedBasisReason(_ candidates: [CandidateRun], copy: UserFacingCopy) -> String? {
        guard let lead = candidates.first else { return nil }
        for candidate in candidates.dropFirst() {
            if let reason = CandidateRun.basisMismatch(lead.basis, candidate.basis, copy: copy) {
                return reason
            }
        }
        return nil
    }

    /// Keep the lead basis. A mismatched candidate stays out of the comparison
    /// instead of being scored against a different occupancy or setpoint.
    private static func sameBasis(asLeadOf candidates: [CandidateRun]) -> [CandidateRun] {
        guard let lead = candidates.first else { return [] }
        return candidates.filter { CandidateRun.basisMismatch(lead.basis, $0.basis) == nil }
    }

    /// A partial miss is a constraint, shown before comfort and cost.
    /// Total failure is handled earlier and does not reach here.
    private static func constraintCard(_ candidates: [CandidateRun], copy: UserFacingCopy) -> RecommendationCard? {
        let partial = candidates.filter { candidate in
            guard let evalCount = number(candidate, "seat_eval_count"),
                  let passCount = number(candidate, "seat_pass_count") else {
                return false
            }
            return evalCount > 0 && passCount < evalCount
        }
        guard !partial.isEmpty else { return nil }
        return RecommendationCard(
            id: "constraint",
            kind: .explanation,
            title: copy.recommendPartialTitle,
            detail: copy.recommendPartialDetail,
            citedRunIDs: partial.map(\.identity.runID),
            qualityPassed: true,
            assumptions: assumptionLines(partial, copy: copy)
        )
    }

    /// Supply-height (or other supply-patch) change that moved seat temperature or coverage.
    private static func comfortCard(_ candidates: [CandidateRun], copy: UserFacingCopy) -> RecommendationCard? {
        guard candidates.count >= 2 else { return nil }
        let changed = candidates.filter { candidate in
            candidates.contains { other in
                candidate.identity.runID != other.identity.runID
                    && geometryDiffers(candidate, other)
                    && comfortMetricDiffers(candidate, other)
            }
        }
        guard changed.count >= 2 else { return nil }
        return RecommendationCard(
            id: "comfort",
            kind: .comfort,
            title: copy.recommendComfortTitle,
            detail: copy.recommendComfortDetail,
            citedRunIDs: changed.map(\.identity.runID),
            qualityPassed: true,
            assumptions: assumptionLines(changed, copy: copy)
        )
    }

    /// L1 day-cost delta, or an explicit tie, under one basis. Cites L1 run IDs.
    private static func operationCard(_ candidates: [CandidateRun], copy: UserFacingCopy) -> RecommendationCard? {
        let priced = candidates.filter {
            $0.l1Identity != nil && $0.dayCost.cost != nil && $0.dayCost.electricPowerW != nil
        }
        guard priced.count >= 2,
              let low = priced.min(by: { ($0.dayCost.cost ?? 0) < ($1.dayCost.cost ?? 0) }),
              let high = priced.max(by: { ($0.dayCost.cost ?? 0) < ($1.dayCost.cost ?? 0) }),
              let saved = CostAccounting.savingsHKD(high.dayCost, low.dayCost, basisMismatch: nil),
              let currency = high.dayCost.currency else {
            return nil
        }
        let l1IDs = priced.compactMap(\.l1Identity?.runID)
        let lever = copy.recommendOperationLever + " "
        let detail: String
        if saved == 0 {
            detail = lever + copy.recommendOperationTie
        } else {
            detail = lever + copy.recommendOperationSavings(UserFacingCopy.displayNumber(saved), currency: currency)
        }
        return RecommendationCard(
            id: "operation",
            kind: .operation,
            title: copy.recommendOperationTitle,
            detail: detail,
            citedRunIDs: l1IDs,
            qualityPassed: true,
            assumptions: assumptionLines(priced, copy: copy)
        )
    }

    /// Installation stays unquoted. Assumptions travel with the card; payback does not.
    private static func retrofitCard(_ candidates: [CandidateRun], copy: UserFacingCopy) -> RecommendationCard? {
        guard !candidates.isEmpty else { return nil }
        let assumptions = assumptionLines(candidates, copy: copy) + [copy.recommendRetrofitAssumption]
        return RecommendationCard(
            id: "retrofit",
            kind: .retrofit,
            title: copy.recommendRetrofitTitle,
            detail: copy.recommendRetrofitDetail,
            citedRunIDs: candidates.map(\.identity.runID),
            qualityPassed: candidates.allSatisfy { $0.quality == .passed },
            assumptions: assumptions,
            quoteStatus: copy.awaitingQuote,
            payback: nil
        )
    }

    private static func explanation(
        id: String,
        title: String,
        detail: String,
        candidates: [CandidateRun]
    ) -> RecommendationCard {
        RecommendationCard(
            id: id,
            kind: .explanation,
            title: title,
            detail: detail,
            citedRunIDs: candidates.map(\.identity.runID),
            qualityPassed: false
        )
    }

    private static func geometryDiffers(_ a: CandidateRun, _ b: CandidateRun) -> Bool {
        guard let left = a.draft.hvac?.supply, let right = b.draft.hvac?.supply else { return false }
        return left.z0.value != right.z0.value
            || left.z1.value != right.z1.value
            || left.s0.value != right.s0.value
            || left.s1.value != right.s1.value
            || left.wall != right.wall
    }

    private static func comfortMetricDiffers(_ a: CandidateRun, _ b: CandidateRun) -> Bool {
        for name in ["seat_t_c_min", "seat_t_c_max", "seat_pass_ratio"] {
            guard let left = number(a, name), let right = number(b, name), left != right else { continue }
            return true
        }
        return false
    }

    private static func metric(_ candidate: CandidateRun, _ name: String) -> ResultMetric? {
        candidate.metrics.first { $0.name == name }
    }

    private static func number(_ candidate: CandidateRun, _ name: String) -> Double? {
        guard let row = metric(candidate, name), !row.omitted else { return nil }
        return row.value
    }

    /// Comfort references and the tariff sentence already stored on the pinned draft.
    private static func assumptionLines(_ candidates: [CandidateRun], copy: UserFacingCopy) -> [String] {
        var lines: [String] = []
        for candidate in candidates {
            if let comfort = candidate.draft.occupancy?.comfort {
                let quantities: [(String, PhysicalQuantity)] = [
                    ("mrtC", comfort.mrtC),
                    ("rhPct", comfort.rhPct),
                    ("clo", comfort.clo),
                    ("met", comfort.met),
                ]
                for (key, quantity) in quantities {
                    guard let reference = quantity.reference else { continue }
                    let line = copy.comfortAssumptionLine(
                        key: key,
                        quantity: UserFacingCopy.displayQuantity(quantity.value, unit: quantity.unit),
                        reference: reference
                    )
                    if !lines.contains(line) {
                        lines.append(line)
                    }
                }
            }
            if let reference = candidate.draft.costAssumptions?.reference, !lines.contains(reference) {
                lines.append(reference)
            }
            let quote = candidate.dayCost.retrofitQuote
            if !quote.isEmpty && !lines.contains(quote) {
                lines.append(quote)
            }
        }
        return lines
    }
}
