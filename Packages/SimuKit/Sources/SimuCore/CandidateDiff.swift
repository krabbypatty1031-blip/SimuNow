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
    /// a single scheme has nothing to subtract. Sentences follow `copy`.
    public static func build(
        from candidates: [CandidateRun],
        copy: UserFacingCopy = .english
    ) -> CandidatePairDiff? {
        guard candidates.count >= 2 else { return nil }
        let first = candidates[0]
        let second = candidates[1]
        return CandidatePairDiff(
            firstName: first.name,
            secondName: second.name,
            inputChanges: inputChanges(first, second, copy: copy),
            resultDeltas: resultDeltas(first, second, copy: copy),
            basisMismatchReason: CandidateRun.basisMismatch(first.basis, second.basis, copy: copy)
        )
    }

    // MARK: - Input changes

    /// Basis levers first (they gate what a comparison even means), then
    /// the supply terminal, then windows, then the room shell.
    private static func inputChanges(
        _ first: CandidateRun,
        _ second: CandidateRun,
        copy: UserFacingCopy
    ) -> [InputChange] {
        var changes: [InputChange] = []
        appendNumeric(
            &changes, field: "occupantCount", copy: copy, unit: copy.language == .english ? "people" : "人",
            from: first.basis.occupantCount, to: second.basis.occupantCount
        )
        // Occupied hours carry clock strings, not one number; the sentence
        // holds the exact times and the guard collects them from the pair.
        if first.basis.weatherMonth != second.basis.weatherMonth
            || first.basis.weatherDay != second.basis.weatherDay {
            changes.append(
                InputChange(
                    field: "weatherDay",
                    label: copy.pairDiffLabel("weatherDay"),
                    fromValue: nil,
                    toValue: nil,
                    unit: "",
                    sentence: copy.pairChangedWeatherDay(
                        from: String(format: "%02d-%02d", first.basis.weatherMonth, first.basis.weatherDay),
                        to: String(format: "%02d-%02d", second.basis.weatherMonth, second.basis.weatherDay)
                    )
                )
            )
        }
        if first.basis.occupiedStart != second.basis.occupiedStart
            || first.basis.occupiedEnd != second.basis.occupiedEnd {
            changes.append(
                InputChange(
                    field: "occupiedHours",
                    label: copy.pairDiffLabel("occupiedHours"),
                    fromValue: nil,
                    toValue: nil,
                    unit: "",
                    sentence: copy.pairChangedOccupiedHours(
                        fromStart: first.basis.occupiedStart,
                        fromEnd: first.basis.occupiedEnd,
                        toStart: second.basis.occupiedStart,
                        toEnd: second.basis.occupiedEnd
                    )
                )
            )
        }
        appendNumeric(
            &changes, field: "setpointC", copy: copy, unit: "°C",
            from: first.basis.setpointC, to: second.basis.setpointC
        )
        appendNumeric(
            &changes, field: "supplyTemperatureC", copy: copy, unit: "°C",
            from: first.basis.supplyTemperatureC, to: second.basis.supplyTemperatureC
        )
        appendSupplyChanges(&changes, first: first, second: second, copy: copy)
        appendWindowChanges(&changes, first: first, second: second, copy: copy)
        appendRoomChanges(&changes, first: first, second: second, copy: copy)
        return changes
    }

    private static func appendSupplyChanges(
        _ changes: inout [InputChange],
        first: CandidateRun,
        second: CandidateRun,
        copy: UserFacingCopy
    ) {
        guard let left = first.draft.hvac?.supply,
            let right = second.draft.hvac?.supply else {
            return
        }
        if left.wall != right.wall {
            changes.append(
                InputChange(
                    field: "supplyWall",
                    label: copy.pairDiffLabel("supplyWall"),
                    fromValue: nil,
                    toValue: nil,
                    unit: "",
                    sentence: copy.pairMovedSupply(
                        fromWall: copy.wallTitle(left.wall),
                        toWall: copy.wallTitle(right.wall)
                    )
                )
            )
        }
        appendNumeric(&changes, field: "supplyZ0M", copy: copy, unit: "m", from: left.z0.value, to: right.z0.value)
        appendNumeric(&changes, field: "supplyZ1M", copy: copy, unit: "m", from: left.z1.value, to: right.z1.value)
        appendNumeric(&changes, field: "supplyS0M", copy: copy, unit: "m", from: left.s0.value, to: right.s0.value)
        appendNumeric(&changes, field: "supplyS1M", copy: copy, unit: "m", from: left.s1.value, to: right.s1.value)
        if let leftSpeed = first.draft.hvac?.supplySpeedMs.value,
            let rightSpeed = second.draft.hvac?.supplySpeedMs.value,
            leftSpeed != rightSpeed {
            changes.append(
                InputChange(
                    field: "supplySpeedMs",
                    label: copy.pairDiffLabel("supplySpeedMs"),
                    fromValue: leftSpeed,
                    toValue: rightSpeed,
                    unit: "m/s",
                    sentence: copy.pairChangedNumeric(
                        label: copy.pairDiffLabel("supplySpeedMs"),
                        from: UserFacingCopy.displayNumber(leftSpeed),
                        to: UserFacingCopy.displayNumber(rightSpeed),
                        unit: "m/s"
                    )
                )
            )
        }
    }

    /// Windows enter as count plus total area; per-window geometry stays in
    /// the candidates table, not the diff sentence.
    private static func appendWindowChanges(
        _ changes: inout [InputChange],
        first: CandidateRun,
        second: CandidateRun,
        copy: UserFacingCopy
    ) {
        let leftWindows = first.draft.geometry?.openings.filter { $0.kind == .window } ?? []
        let rightWindows = second.draft.geometry?.openings.filter { $0.kind == .window } ?? []
        if leftWindows.count != rightWindows.count {
            changes.append(
                InputChange(
                    field: "windowCount",
                    label: copy.pairDiffLabel("windowCount"),
                    fromValue: Double(leftWindows.count),
                    toValue: Double(rightWindows.count),
                    unit: copy.language == .english ? "windows" : "扇",
                    sentence: copy.pairChangedWindows(from: leftWindows.count, to: rightWindows.count)
                )
            )
        }
        let leftArea = leftWindows.reduce(0.0) { $0 + $1.patchAreaM2 }
        let rightArea = rightWindows.reduce(0.0) { $0 + $1.patchAreaM2 }
        if leftArea != rightArea {
            appendNumeric(
                &changes, field: "windowAreaM2", copy: copy, unit: "m²",
                from: leftArea, to: rightArea
            )
        }
    }

    private static func appendRoomChanges(
        _ changes: inout [InputChange],
        first: CandidateRun,
        second: CandidateRun,
        copy: UserFacingCopy
    ) {
        // Geometry is optional in the draft; a missing side stays silent.
        appendNumeric(
            &changes, field: "roomLengthM", copy: copy, unit: "m",
            from: first.draft.geometry?.sizeX.value, to: second.draft.geometry?.sizeX.value
        )
        appendNumeric(
            &changes, field: "roomWidthM", copy: copy, unit: "m",
            from: first.draft.geometry?.sizeY.value, to: second.draft.geometry?.sizeY.value
        )
        appendNumeric(
            &changes, field: "roomHeightM", copy: copy, unit: "m",
            from: first.draft.geometry?.sizeZ.value, to: second.draft.geometry?.sizeZ.value
        )
    }

    private static func appendNumeric(
        _ changes: inout [InputChange],
        field: String,
        copy: UserFacingCopy,
        unit: String,
        from: Double?,
        to: Double?
    ) {
        guard let from, let to, from != to else { return }
        let label = copy.pairDiffLabel(field)
        changes.append(
            InputChange(
                field: field,
                label: label,
                fromValue: from,
                toValue: to,
                unit: unit,
                sentence: copy.pairChangedNumeric(
                    label: label,
                    from: UserFacingCopy.displayNumber(from),
                    to: UserFacingCopy.displayNumber(to),
                    unit: unit
                )
            )
        )
    }

    // MARK: - Result deltas

    /// Grouped by the report dimensions the user asked to keep: energy,
    /// comfort, flow. Labels match `UserFacingCopy.metricTitle` so the app,
    /// the PDF and the AI report read the same names.
    private static func resultDeltas(
        _ first: CandidateRun,
        _ second: CandidateRun,
        copy: UserFacingCopy
    ) -> [ResultDelta] {
        var deltas: [ResultDelta] = []
        // Energy: the L1 chain, day and report-layer yearly totals.
        appendDelta(
            &deltas, dimension: "energy", field: "coolingW", copy: copy, unit: "W",
            first: metricNumber(first, "q_cool_w"), second: metricNumber(second, "q_cool_w")
        )
        appendDelta(
            &deltas, dimension: "energy", field: "electricPowerW", copy: copy, unit: "W",
            first: metricNumber(first, "p_elec_w"), second: metricNumber(second, "p_elec_w")
        )
        appendDelta(
            &deltas, dimension: "energy", field: "dayEnergyKWh", copy: copy, unit: "kWh",
            first: first.dayCost.energyKWh, second: second.dayCost.energyKWh
        )
        appendDelta(
            &deltas, dimension: "energy", field: "dayCost", copy: copy,
            unit: first.dayCost.currency ?? "",
            first: first.dayCost.cost, second: second.dayCost.cost
        )
        appendDelta(
            &deltas, dimension: "energy", field: "annualEnergyKWh", copy: copy, unit: "kWh",
            first: CostAccounting.annualEnergyKWh(from: first.dayCost.energyKWh),
            second: CostAccounting.annualEnergyKWh(from: second.dayCost.energyKWh)
        )
        appendDelta(
            &deltas, dimension: "energy", field: "annualCost", copy: copy,
            unit: first.dayCost.currency ?? "",
            first: CostAccounting.annualCost(from: first.dayCost.cost),
            second: CostAccounting.annualCost(from: second.dayCost.cost)
        )
        // Comfort: seat-level temperature band and pass coverage.
        appendDelta(
            &deltas, dimension: "comfort", field: "seatTMinC", copy: copy, unit: "°C",
            first: metricNumber(first, "seat_t_c_min"), second: metricNumber(second, "seat_t_c_min")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatTMaxC", copy: copy, unit: "°C",
            first: metricNumber(first, "seat_t_c_max"), second: metricNumber(second, "seat_t_c_max")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatPassRatio", copy: copy, unit: "",
            first: metricNumber(first, "seat_pass_ratio"), second: metricNumber(second, "seat_pass_ratio")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatPMVMax", copy: copy, unit: "",
            first: metricNumber(first, "seat_pmv_max"), second: metricNumber(second, "seat_pmv_max")
        )
        appendDelta(
            &deltas, dimension: "comfort", field: "seatPPDMax", copy: copy, unit: "%",
            first: metricNumber(first, "seat_ppd_max"), second: metricNumber(second, "seat_ppd_max")
        )
        // Flow: seat-level air speed.
        appendDelta(
            &deltas, dimension: "flow", field: "seatUMagMax", copy: copy, unit: "m/s",
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
        copy: UserFacingCopy,
        unit: String,
        first: Double?,
        second: Double?
    ) {
        guard let first, let second else { return }
        deltas.append(
            ResultDelta(
                dimension: dimension,
                field: field,
                label: copy.pairDiffLabel(field),
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
