import Foundation

/// One seat as the demo gates see it.
///
/// `omitted` seats (outside the fluid, or otherwise dropped before
/// evaluation) stay out of the denominator. They are not failures.
public struct FeasibilitySeat: Equatable, Sendable {
    public var id: String
    public var tC: Double
    public var uMag: Double
    public var pmv: Double?
    /// Near-zero speeds still use the 0.25 m/s gate; the flag only marks them.
    public var lowSpeedAbsoluteError: Bool
    public var omitted: Bool

    public init(
        id: String,
        tC: Double,
        uMag: Double,
        pmv: Double? = nil,
        lowSpeedAbsoluteError: Bool = false,
        omitted: Bool = false
    ) {
        self.id = id
        self.tC = tC
        self.uMag = uMag
        self.pmv = pmv
        self.lowSpeedAbsoluteError = lowSpeedAbsoluteError
        self.omitted = omitted
    }

    /// A quality-passed wire sample. Omitted seats never enter `seatSamples`.
    public init(sample: SeatSample) {
        self.init(
            id: sample.id,
            tC: sample.tC,
            uMag: sample.uMag,
            pmv: sample.pmv,
            lowSpeedAbsoluteError: sample.lowSpeedAbsoluteError ?? false
        )
    }
}

/// One comparison-card row. The label is a model gate, not a satisfaction rate.
public struct FeasibilityDisplay: Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Demo seat gates for a quality-passed L2 field. Not a standards certification.
///
/// Coverage is pass count / evaluated count. Out-of-domain seats leave the
/// denominator. A missing field omits the ratio instead of reporting 0.
public enum SeatFeasibility: Sendable {
    public static let airLowC = 23.0
    public static let airHighC = 26.0
    public static let bandCenterC = 24.5
    public static let speedGateMps = 0.25
    public static let pmvLimit = 0.5

    /// ISO 7730 air applicability. Outside this the seat is excluded, not failed.
    public static let isoAirLowC = 10.0
    public static let isoAirHighC = 30.0
    public static let isoSpeedHighMps = 1.0

    public static let coverageLabel = "合适的座位"
    public static let worstSeatLabel = "最不合适的座位"

    private static let omitReason = "not evaluable: no quality-passed seat samples"
    private static let method = "l2_seat_gate"
    private static let notModeled = "not_modeled"

    /// Numeric rows plus id/reason rows. Ids ride in `reason` because a metric value is a number.
    public static func metrics(seats: [FeasibilitySeat]?, qualityPassed: Bool) -> [ResultMetric] {
        guard qualityPassed, let seats, !seats.isEmpty else {
            return omittedAll(omitReason)
        }
        let (evaluated, excluded) = split(seats)
        guard !evaluated.isEmpty else {
            let ids = excluded.map(\.id).joined(separator: ", ")
            let shown = ids.isEmpty ? "none" : ids
            return omittedAll("not evaluable: no seat inside the model domain (excluded: \(shown); 不计入分母)")
        }

        var passCount = 0
        var hitGates: [String] = []
        for seat in evaluated {
            let gates = failedGates(seat)
            if gates.isEmpty {
                passCount += 1
            } else {
                for gate in gates where !hitGates.contains(gate) {
                    hitGates.append(gate)
                }
            }
        }

        let evalCount = evaluated.count
        let ratio = Double(passCount) / Double(evalCount)
        let worst = worstSeat(evaluated)
        var worstReason = failedGates(worst).joined(separator: "、")
        if worstReason.isEmpty {
            // A fully covered field still names the seat farthest from band center.
            worstReason = "偏离温度带中心 24.5 °C 最大"
        }
        if worst.lowSpeedAbsoluteError {
            worstReason += "；低速绝对误差"
        }

        var notes: [String] = []
        if !excluded.isEmpty {
            let ids = excluded.map(\.id).joined(separator: ", ")
            notes.append("排除 \(excluded.count) 座（域外或 omitted，不计入分母）：\(ids)")
        }
        let lowSpeed = evaluated.filter(\.lowSpeedAbsoluteError).map(\.id)
        if !lowSpeed.isEmpty {
            notes.append("低速绝对误差座位仍用风速门：" + lowSpeed.joined(separator: ", "))
        }
        let sharedNote = notes.isEmpty ? nil : notes.joined(separator: "；")

        // All-fail names the gates. It does not invent a recommended scheme.
        let infeasibleOmitted = passCount > 0
        let infeasibleReason = passCount == 0 ? hitGates.joined(separator: "、") : "未触发：已有座位通过模型门"

        return [
            row("seat_pass_ratio", unit: "1", value: ratio, omitted: false, reason: sharedNote),
            row("seat_pass_count", unit: "count", value: Double(passCount), omitted: false, reason: sharedNote),
            row("seat_eval_count", unit: "count", value: Double(evalCount), omitted: false, reason: sharedNote),
            row("worst_seat_id", unit: "id", value: nil, omitted: false, reason: worst.id),
            row("worst_seat_reason", unit: "text", value: nil, omitted: false, reason: worstReason),
            row("infeasibleReason", unit: "text", value: nil, omitted: infeasibleOmitted, reason: infeasibleReason),
        ]
    }

    /// Omitted coverage is 不可评价. A real zero ratio stays 0%, with the counts beside it.
    public static func coverageText(metrics: [ResultMetric]) -> String {
        guard let ratio = metrics.first(where: { $0.name == "seat_pass_ratio" }),
              !ratio.omitted,
              ratio.value != nil,
              let pass = metrics.first(where: { $0.name == "seat_pass_count" })?.value,
              let evalCount = metrics.first(where: { $0.name == "seat_eval_count" })?.value
        else {
            return "不可评价"
        }
        return String(format: "%.0f 个中 %.0f 个合适", evalCount, pass)
    }

    public static func worstSeatText(metrics: [ResultMetric]) -> String {
        guard let idMetric = metrics.first(where: { $0.name == "worst_seat_id" }),
              !idMetric.omitted,
              let id = idMetric.reason,
              !id.isEmpty
        else {
            return "不可评价"
        }
        if let why = metrics.first(where: { $0.name == "worst_seat_reason" })?.reason, !why.isEmpty {
            return "\(displaySeatID(id))：\(UserFacingCopy.gateTitle(why))"
        }
        return displaySeatID(id)
    }

    /// S4 → 座位 4. Unknown prefixes stay as a generic 座位.
    private static func displaySeatID(_ id: String) -> String {
        if id.count >= 2, id.first?.isLetter == true, let number = Int(id.dropFirst()) {
            return "座位 \(number)"
        }
        return "座位"
    }

    public static func comparisonRows(metrics: [ResultMetric]) -> [FeasibilityDisplay] {
        [
            FeasibilityDisplay(label: coverageLabel, value: coverageText(metrics: metrics)),
            FeasibilityDisplay(label: worstSeatLabel, value: worstSeatText(metrics: metrics)),
        ]
    }

    private static func omittedAll(_ reason: String) -> [ResultMetric] {
        [
            ("seat_pass_ratio", "1"),
            ("seat_pass_count", "count"),
            ("seat_eval_count", "count"),
            ("worst_seat_id", "id"),
            ("worst_seat_reason", "text"),
            ("infeasibleReason", "text"),
        ].map { name, unit in
            row(name, unit: unit, value: nil, omitted: true, reason: reason)
        }
    }

    private static func row(
        _ name: String,
        unit: String,
        value: Double?,
        omitted: Bool,
        reason: String?
    ) -> ResultMetric {
        ResultMetric(
            name: name,
            value: value,
            unit: unit,
            method: omitted ? notModeled : method,
            fidelity: .l2,
            omitted: omitted,
            reason: reason
        )
    }

    /// Absent PMV is not a miss. Present PMV must sit in [-0.5, 0.5].
    private static func failedGates(_ seat: FeasibilitySeat) -> [String] {
        var gates: [String] = []
        if !(airLowC <= seat.tC && seat.tC <= airHighC) {
            gates.append("温度门")
        }
        if seat.uMag > speedGateMps {
            gates.append("风速门")
        }
        if let pmv = seat.pmv, !(-pmvLimit <= pmv && pmv <= pmvLimit) {
            gates.append("PMV门")
        }
        return gates
    }

    private static func split(_ seats: [FeasibilitySeat]) -> (evaluated: [FeasibilitySeat], excluded: [FeasibilitySeat]) {
        var excluded: [FeasibilitySeat] = []
        var candidates: [FeasibilitySeat] = []
        for seat in seats {
            if seat.omitted {
                excluded.append(seat)
                continue
            }
            let inAir = isoAirLowC <= seat.tC && seat.tC <= isoAirHighC
                && 0 <= seat.uMag && seat.uMag <= isoSpeedHighMps
            if !inAir {
                excluded.append(seat)
                continue
            }
            candidates.append(seat)
        }
        // Siblings with a PMV mean comfort ran. A seat left without PMV was
        // outside ISO applicability, so it leaves the denominator too.
        let anyPMV = candidates.contains { $0.pmv != nil }
        var evaluated: [FeasibilitySeat] = []
        for seat in candidates {
            if anyPMV && seat.pmv == nil {
                excluded.append(seat)
                continue
            }
            evaluated.append(seat)
        }
        return (evaluated, excluded)
    }

    /// Largest |tC - 24.5 °C|; higher speed wins a tie.
    private static func worstSeat(_ seats: [FeasibilitySeat]) -> FeasibilitySeat {
        seats.max { lhs, rhs in
            let left = abs(lhs.tC - bandCenterC)
            let right = abs(rhs.tC - bandCenterC)
            if left != right {
                return left < right
            }
            return lhs.uMag < rhs.uMag
        } ?? seats[0]
    }
}
