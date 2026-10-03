import Foundation

/// Field-level differences between the first two pinned candidates.
/// Subtraction happens here, in code, so every delta the AI quotes is
/// already evidence - the AI narrates, it never does its own math.
public struct CandidatePairDiff: Codable, Equatable, Sendable {
    /// One user-visible input change between the two pinned drafts.
    public struct InputChange: Codable, Equatable, Sendable {
        public var field: String
        public var label: String
        public var fromValue: Double?
        public var toValue: Double?
        public var unit: String
        /// Plain-language sentence. Numbers use the two-decimal display the
        /// rest of the UI uses so the narration guard accepts them.
        public var sentence: String

        public init(
            field: String,
            label: String,
            fromValue: Double?,
            toValue: Double?,
            unit: String,
            sentence: String
        ) {
            self.field = field
            self.label = label
            self.fromValue = fromValue
            self.toValue = toValue
            self.unit = unit
            self.sentence = sentence
        }
    }

    /// One dimension-grouped result delta. `delta` is second - first,
    /// half-up to two decimals so guarded prose quotes it as stored.
    public struct ResultDelta: Codable, Equatable, Sendable {
        /// Report dimension: "energy", "comfort" or "flow". A string, not
        /// an enum, so the Python evidence pack stays structurally in sync.
        public var dimension: String
        public var field: String
        public var label: String
        public var first: Double?
        public var second: Double?
        public var delta: Double?
        public var unit: String

        public init(
            dimension: String,
            field: String,
            label: String,
            first: Double?,
            second: Double?,
            delta: Double?,
            unit: String
        ) {
            self.dimension = dimension
            self.field = field
            self.label = label
            self.first = first
            self.second = second
            self.delta = delta
            self.unit = unit
        }
    }

    public var firstName: String
    public var secondName: String
    public var inputChanges: [InputChange]
    public var resultDeltas: [ResultDelta]
    /// Non-nil when the two candidates break the shared comparison basis.
    /// The old hard block becomes this honest sentence the AI must state.
    public var basisMismatchReason: String?

    public init(
        firstName: String,
        secondName: String,
        inputChanges: [InputChange],
        resultDeltas: [ResultDelta],
        basisMismatchReason: String? = nil
    ) {
        self.firstName = firstName
        self.secondName = secondName
        self.inputChanges = inputChanges
        self.resultDeltas = resultDeltas
        self.basisMismatchReason = basisMismatchReason
    }

    /// Diff of the first two pins. Fewer than two pins returns nil -
    /// a single scheme has nothing to subtract.
    public static func build(from candidates: [CandidateRun]) -> CandidatePairDiff? {
        guard candidates.count >= 2 else { return nil }
        let first = candidates[0]
        let second = candidates[1]
        return CandidatePairDiff(
            firstName: first.name,
            secondName: second.name,
            inputChanges: inputChanges(first, second),
            resultDeltas: resultDeltas(first, second),
            basisMismatchReason: CandidateRun.basisMismatch(first.basis, second.basis)
        )
    }

    // MARK: - Input changes

    /// Basis levers first (they gate what a comparison even means), then
    /// the supply terminal, then windows, then the room shell.
    private static func inputChanges(
        _ first: CandidateRun,
        _ second: CandidateRun
    ) -> [InputChange] {
        var changes: [InputChange] = []
        appendNumeric(
            &changes, field: "occupantCount", label: "人数", unit: "人",
            from: first.basis.occupantCount, to: second.basis.occupantCount
        ) { from, to in
            "人数从 \(UserFacingCopy.displayNumber(from)) 人改为 \(UserFacingCopy.displayNumber(to)) 人"
        }
        // Occupied hours carry clock strings, not one number; the sentence
        // holds the exact times and the guard collects them from the pair.
        if first.basis.occupiedStart != second.basis.occupiedStart
            || first.basis.occupiedEnd != second.basis.occupiedEnd {
            changes.append(
                InputChange(
                    field: "occupiedHours",
                    label: "使用时间",
                    fromValue: nil,
                    toValue: nil,
                    unit: "",
                    sentence: "使用时间从 \(first.basis.occupiedStart)–\(first.basis.occupiedEnd) 改为 \(second.basis.occupiedStart)–\(second.basis.occupiedEnd)"
                )
            )
        }
        appendNumeric(
            &changes, field: "setpointC", label: "设定温度", unit: "°C",
            from: first.basis.setpointC, to: second.basis.setpointC
        ) { from, to in
            "设定温度从 \(UserFacingCopy.displayNumber(from)) °C 改为 \(UserFacingCopy.displayNumber(to)) °C"
        }
        appendNumeric(
            &changes, field: "supplyTemperatureC", label: "出风温度", unit: "°C",
            from: first.basis.supplyTemperatureC, to: second.basis.supplyTemperatureC
        ) { from, to in
            "出风温度从 \(UserFacingCopy.displayNumber(from)) °C 改为 \(UserFacingCopy.displayNumber(to)) °C"
        }
        appendSupplyChanges(&changes, first: first, second: second)
        appendWindowChanges(&changes, first: first, second: second)
        appendRoomChanges(&changes, first: first, second: second)
        return changes
    }

    private static func appendSupplyChanges(
        _ changes: inout [InputChange],
        first: CandidateRun,
        second: CandidateRun
    ) {
        guard let left = first.draft.hvac?.supply,
            let right = second.draft.hvac?.supply else {
            return
        }
        if left.wall != right.wall {
            changes.append(
                InputChange(
                    field: "supplyWall",
                    label: "出风口所在墙",
                    fromValue: nil,
                    toValue: nil,
                    unit: "",
                    sentence: "出风口从\(UserFacingCopy.wallTitle(left.wall))挪到\(UserFacingCopy.wallTitle(right.wall))"
                )
            )
        }
        appendNumeric(
            &changes, field: "supplyZ0M", label: "出风口下沿", unit: "m",
            from: left.z0.value, to: right.z0.value
        ) { from, to in
            "出风口下沿从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
        appendNumeric(
            &changes, field: "supplyZ1M", label: "出风口上沿", unit: "m",
            from: left.z1.value, to: right.z1.value
        ) { from, to in
            "出风口上沿从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
        appendNumeric(
            &changes, field: "supplyS0M", label: "出风口沿墙起点", unit: "m",
            from: left.s0.value, to: right.s0.value
        ) { from, to in
            "出风口沿墙位置从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
        appendNumeric(
            &changes, field: "supplyS1M", label: "出风口沿墙终点", unit: "m",
            from: left.s1.value, to: right.s1.value
        ) { from, to in
            "出风口沿墙终点从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
        if let leftSpeed = first.draft.hvac?.supplySpeedMs.value,
            let rightSpeed = second.draft.hvac?.supplySpeedMs.value,
            leftSpeed != rightSpeed {
            changes.append(
                InputChange(
                    field: "supplySpeedMs",
                    label: "出风速度",
                    fromValue: leftSpeed,
                    toValue: rightSpeed,
                    unit: "m/s",
                    sentence: "出风速度从 \(UserFacingCopy.displayNumber(leftSpeed)) m/s 改为 \(UserFacingCopy.displayNumber(rightSpeed)) m/s"
                )
            )
        }
    }

    /// Windows enter as count plus total area; per-window geometry stays in
    /// the candidates table, not the diff sentence.
    private static func appendWindowChanges(
        _ changes: inout [InputChange],
        first: CandidateRun,
        second: CandidateRun
    ) {
        let leftWindows = first.draft.geometry?.openings.filter { $0.kind == .window } ?? []
        let rightWindows = second.draft.geometry?.openings.filter { $0.kind == .window } ?? []
        if leftWindows.count != rightWindows.count {
            changes.append(
                InputChange(
                    field: "windowCount",
                    label: "窗户数量",
                    fromValue: Double(leftWindows.count),
                    toValue: Double(rightWindows.count),
                    unit: "扇",
                    sentence: "窗户从 \(leftWindows.count) 扇改为 \(rightWindows.count) 扇"
                )
            )
        }
        let leftArea = leftWindows.reduce(0.0) { $0 + $1.patchAreaM2 }
        let rightArea = rightWindows.reduce(0.0) { $0 + $1.patchAreaM2 }
        if leftArea != rightArea {
            changes.append(
                InputChange(
                    field: "windowAreaM2",
                    label: "窗户总面积",
                    fromValue: leftArea,
                    toValue: rightArea,
                    unit: "m²",
                    sentence: "窗户总面积从 \(UserFacingCopy.displayNumber(leftArea)) m² 改为 \(UserFacingCopy.displayNumber(rightArea)) m²"
                )
            )
        }
    }

    private static func appendRoomChanges(
        _ changes: inout [InputChange],
        first: CandidateRun,
        second: CandidateRun
    ) {
        // Geometry is optional in the draft; a missing side stays silent.
        appendNumeric(
            &changes, field: "roomLengthM", label: "房间长度", unit: "m",
            from: first.draft.geometry?.sizeX.value, to: second.draft.geometry?.sizeX.value
        ) { from, to in
            "房间长度从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
        appendNumeric(
            &changes, field: "roomWidthM", label: "房间宽度", unit: "m",
            from: first.draft.geometry?.sizeY.value, to: second.draft.geometry?.sizeY.value
        ) { from, to in
            "房间宽度从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
        appendNumeric(
            &changes, field: "roomHeightM", label: "房间高度", unit: "m",
            from: first.draft.geometry?.sizeZ.value, to: second.draft.geometry?.sizeZ.value
        ) { from, to in
            "房间高度从 \(UserFacingCopy.displayNumber(from)) m 改为 \(UserFacingCopy.displayNumber(to)) m"
        }
    }

    private static func appendNumeric(
        _ changes: inout [InputChange],
        field: String,
        label: String,
        unit: String,
        from: Double?,
        to: Double?,
        sentence: (Double, Double) -> String
    ) {
        guard let from, let to, from != to else { return }
        changes.append(
            InputChange(
                field: field,
                label: label,
                fromValue: from,
                toValue: to,
                unit: unit,
                sentence: sentence(from, to)
            )
        )
    }

    // MARK: - Result deltas

    /// Grouped by the report dimensions the user asked to keep: energy,
    /// comfort, flow. Labels match `UserFacingCopy.metricTitle` so the app,
    /// the PDF and the AI report read the same names.
    private static func resultDeltas(
        _ first: CandidateRun,
        _ second: CandidateRun
    ) -> [ResultDelta] {
        var deltas: [ResultDelta] = []
        // Energy: the L1 chain, day and report-layer yearly totals.
        appendDelta(
            &deltas, dimension: "energy", field: "coolingW", label: "制冷量", unit: "W",
            first: metricNumber(first, "q_cool_w"), second: metricNumber(second, "q_cool_w")
        )
        appendDelta(
            &deltas, dimension: "energy", field: "electricPowerW", label: "电功率", unit: "W",
            first: metricNumber(first, "p_elec_w"), second: metricNumber(second, "p_elec_w")
        )
        appendDelta(
            &deltas, dimension: "energy", field: "dayEnergyKWh", label: "代表日用电", unit: "kWh",
            first: first.dayCost.energyKWh, second: second.dayCost.energyKWh
        )
        appendDelta(
            &deltas, dimension: "energy", field: "dayCost", label: "代表日电费",
            unit: first.dayCost.currency ?? "",
            first: first.dayCost.cost, second: second.dayCost.cost
        )
        appendDelta(
            &deltas, dimension: "energy", field: "annualEnergyKWh", label: "全年用电", unit: "kWh",
            first: CostAccounting.annualEnergyKWh(from: first.dayCost.energyKWh),
            second: CostAccounting.annualEnergyKWh(from: second.dayCost.energyKWh)
        )
        appendDelta(
            &deltas, dimension: "energy", field: "annualCost", label: "全年电费",
            unit: first.dayCost.currency ?? "",
            first: CostAccounting.annualCost(from: first.dayCost.cost),
            second: CostAccounting.annualCost(from: second.dayCost.cost)
        )
        // Comfort: seat-level temperature band and pass coverage.
        appendDelta(
            &deltas, dimension: "comfort", field: "seatTMinC", label: "座位最凉", unit: "°C",
            first: metricNumber(first, "seat_t_c_min"), second: metricNumber(second, "seat_t_c_min")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatTMaxC", label: "座位最热", unit: "°C",
            first: metricNumber(first, "seat_t_c_max"), second: metricNumber(second, "seat_t_c_max")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatPassRatio", label: "合适的座位", unit: "",
            first: metricNumber(first, "seat_pass_ratio"), second: metricNumber(second, "seat_pass_ratio")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatPMVMax", label: "冷热是否合适（偏高）", unit: "",
            first: metricNumber(first, "seat_pmv_max"), second: metricNumber(second, "seat_pmv_max")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatPPDMax", label: "不满意比例（最热座位）", unit: "%",
            first: metricNumber(first, "seat_ppd_max"), second: metricNumber(second, "seat_ppd_max")
        )
        // Flow: seat-level air speed.
        appendDelta(
            &deltas, dimension: "flow", field: "seatUMagMax", label: "座位最大风速", unit: "m/s",
            first: metricNumber(first, "seat_u_mag_max"), second: metricNumber(second, "seat_u_mag_max")
        )
        return deltas
    }

    /// Both sides present (a delta of 0 is an honest tie, not an omission);
    /// either side missing leaves the row out rather than half a number.
    private static func appendDelta(
        _ deltas: inout [ResultDelta],
        dimension: String,
        field: String,
        label: String,
        unit: String,
        first: Double?,
        second: Double?
    ) {
        guard let first, let second else { return }
        deltas.append(
            ResultDelta(
                dimension: dimension,
                field: field,
                label: label,
                first: first,
                second: second,
                delta: roundHalfUpTwo(second - first),
                unit: unit
            )
        )
    }

    private static func metricNumber(_ candidate: CandidateRun, _ name: String) -> Double? {
        guard let metric = candidate.metrics.first(where: { $0.name == name }),
            !metric.omitted else {
            return nil
        }
        return metric.value
    }

    /// Half-up to two decimals, matching the UI display form so guarded
    /// prose quotes deltas exactly as stored.
    private static func roundHalfUpTwo(_ value: Double) -> Double {
        let rounded = (value * 100).rounded(.toNearestOrAwayFromZero) / 100
        return rounded == 0 ? 0 : rounded  // avoid -0.0 in evidence JSON
    }
}
