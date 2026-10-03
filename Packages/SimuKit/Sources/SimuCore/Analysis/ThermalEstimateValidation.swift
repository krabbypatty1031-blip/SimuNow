import Foundation

public enum ThermalEstimateValidation {
    public static func sourceIsExplicit(_ source: SourceRecord) -> Bool {
        switch source.kind {
        case .measured, .manufacturer, .preset: return source.reference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .assumed: return source.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        default: return true
        }
    }
    /// Keeps adopted cost arithmetic far from Foundation Decimal's exponent limits.
    /// Zero is meaningful; tiny nonzero inputs remain usable by the power estimator only.
    public static func validateCostNumericInput(_ value: Double) throws {
        guard value.isFinite, value == 0 || (value >= 1e-12 && value <= 1e12) else {
            throw ProjectDataError.contract("费用数值支持范围：电功率 W 与费率/端点须为 0 或 1e−12…1e12；极小非零输入不能作为零价或计算费用。")
        }
    }
    public static func validateWindows(_ windows: [AnalysisTimeWindow], requireNonempty: Bool = true) throws {
        if requireNonempty && windows.isEmpty { throw ProjectDataError.contract("Requested windows are empty") }
        var last = -1
        for w in windows {
            guard w.startMinute >= 0, w.startMinute < w.endMinute, w.endMinute <= 1440, w.startMinute >= last else { throw ProjectDataError.contract("Invalid, unsorted or overlapping reference-day windows") }
            last = w.endMinute
        }
    }
    public static func validateParameter<Q>(_ parameter: PhysicalParameter<Q>, minimum: Double = 0, maximum: Double = 1e12, strictMinimum: Bool = false) throws {
        guard case .known(let v, let source, let bounds) = parameter else { return }
        func valid(_ x: Double) -> Bool { x.isFinite && (strictMinimum ? x > minimum : x >= minimum) && x <= maximum }
        guard valid(v), sourceIsExplicit(source) else { throw ProjectDataError.contract("Invalid \(Q.unit) value or source") }
        if let b = bounds {
            guard valid(b.lower), valid(b.upper), b.lower <= v, v <= b.upper, !b.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectDataError.contract("Invalid nominal/bounds/support range for \(Q.unit)") }
        }
    }
    public static func validatePower(_ config: PowerEstimateConfiguration) throws {
        try validateWindows(config.requestedWindows, requireNonempty: false)
        try validateWindows(config.intervals.map { .init(startMinute: $0.startMinute, endMinute: $0.endMinute) }, requireNonempty: false)
        guard config.intervals.count <= 1440, config.requestedWindows.count <= 1440 else { throw ProjectDataError.contract("Too many power intervals") }
        for interval in config.intervals { try validateParameter(interval.power) }
        if let ids = config.aggregateDeviceIDs, Set(ids).count != ids.count { throw ProjectDataError.contract("Duplicate aggregate devices") }
    }
    public static func powerMissing(_ config: PowerEstimateConfiguration, deviceIDs: [UUID]) -> [AnalysisMissingReason] {
        var out: [AnalysisMissingReason] = []
        func missing(_ code: String, _ path: String, _ reason: String) { out.append(.init(code: code, fieldPath: path, reason: reason)) }
        if config.requestedWindows.isEmpty { missing("power_window_required", "requestedWindows", "请明确请求的参考日窗口。") }
        if config.intervals.isEmpty { missing("power_basis_required", "intervals", "请提供电功率、来源及口径，制冷量不能代替。") }
        if deviceIDs.count > 1 || config.aggregateDeviceIDs != nil {
            guard let ids = config.aggregateDeviceIDs, Set(ids) == Set(deviceIDs), !ids.isEmpty, config.aggregateCoverageNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                missing("power_aggregate_coverage", "aggregateDeviceIDs", "多设备必须明确合计电功率覆盖全部设备及来源；不会默算其中一台。")
                return out
            }
        }
        for (i, interval) in config.intervals.enumerated() where config.requestedWindows.contains(where: { interval.endMinute > $0.startMinute && interval.startMinute < $0.endMinute }) {
            if interval.power.value == nil { missing("power_unknown", "intervals/\(i)/power", "功率未知，不能保存完整电量；草稿小计仅覆盖已知时段。") }
            if interval.basis == .ratedContinuous && config.ratedContinuousConfirmed != true { missing("power_rated_confirmation", "ratedContinuousConfirmed", "明确确认按额定输入功率连续运行的情景；它不是实测平均功率。") }
            if interval.basis == .measuredAverage, case .known(_,let source,_) = interval.power, source.kind != .measured { missing("power_measured_source", "intervals/\(i)/power/source", "实测平均功率需明确实测来源，不能把厂家额定值标为实测。") }
            if interval.basis == .measuredAverage && interval.measurementPeriod?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { missing("power_measurement_period", "intervals/\(i)/measurementPeriod", "实测平均功率需要记录采样日期、时段及适用范围。") }
        }
        for w in config.requestedWindows {
            var cursor = w.startMinute
            for i in config.intervals where i.endMinute > w.startMinute && i.startMinute < w.endMinute {
                if i.startMinute > cursor { missing("power_coverage_gap", "requestedWindows", "\(cursor)…\(min(i.startMinute,w.endMinute)) 分钟无功率覆盖；缺项不是停机。") }
                cursor = max(cursor, min(i.endMinute, w.endMinute))
            }
            if cursor < w.endMinute { missing("power_coverage_gap", "requestedWindows", "\(cursor)…\(w.endMinute) 分钟无功率覆盖。") }
        }
        return out
    }
    public static let heatTerms = ["conductance", "outdoorAir", "infiltration", "internalSensibleHeat", "solarSensibleHeat"]
    public static func validateHeat(_ config: SteadyHeatBalanceConfiguration) throws {
        guard (0...1439).contains(config.conditionMinute) else { throw ProjectDataError.contract("Invalid representative minute") }
        try validateParameter(config.conductance)
        try validateParameter(config.indoorTemperature, minimum: -100, maximum: 100)
        try validateParameter(config.outdoorTemperature, minimum: -100, maximum: 100)
        try validateParameter(config.outdoorAir, maximum: 1e4); try validateParameter(config.infiltration, maximum: 1e4)
        try validateParameter(config.density, minimum: 0, maximum: 10, strictMinimum: true)
        try validateParameter(config.specificHeat, minimum: 0, maximum: 10000, strictMinimum: true)
        try validateParameter(config.internalSensibleHeat); try validateParameter(config.solarSensibleHeat)
        if let capacity = config.sensibleCoolingCapacity { try validateParameter(capacity) }
        if let capacity = config.totalCoolingCapacity { try validateParameter(capacity) }
        if let shr = config.sensibleHeatRatio { try validateParameter(shr, maximum: 1) }
        let excluded = Set(config.excludedTerms)
        guard excluded.count == config.excludedTerms.count, excluded.isSubset(of: Set(heatTerms)) else { throw ProjectDataError.contract("Unknown or duplicate excluded heat term") }
        if let explanations = config.exclusions {
            guard Set(explanations.map(\.term)) == excluded, explanations.count == excluded.count, explanations.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ProjectDataError.contract("Every excluded term needs its own reason") }
        }
        if let coverage = config.coverage {
            guard [coverage.conductanceScope, coverage.internalSensibleScope, coverage.airPropertyConditions].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), sourceIsExplicit(coverage.source) else { throw ProjectDataError.contract("Missing heat scope or property applicability") }
        }
        if let sources = config.internalSources {
            guard sources.count <= 512, Set(sources.map(\.entityID)).count == sources.count else { throw ProjectDataError.contract("Duplicate or excessive internal sources") }
            for s in sources {
                try validateParameter(s.sensible); try validateParameter(s.effectiveFraction, maximum: 1)
                if case .known(_,_,let b)=s.sensible, b != nil { throw ProjectDataError.contract("Internal source list bounds unsupported; explicitly adopt a sourced aggregate interval instead") }
                if case .known(_,_,let b)=s.effectiveFraction, b != nil { throw ProjectDataError.contract("Internal source fraction bounds unsupported; explicitly adopt a sourced aggregate interval instead") }
            }
        }
        let boundedFields = (heatTerms + ["indoorTemperature", "outdoorTemperature", "density", "specificHeat"]).filter { !config.excludedTerms.contains($0) && heatParameter(config, field:$0)?.bounds != nil }
        guard boundedFields.count <= 2, Set(config.sensitivity?.fields ?? []) == Set(boundedFields) else { throw ProjectDataError.contract("Every adopted heat interval must be explicitly selected; at most two interval inputs") }
        if let sensitivity = config.sensitivity {
            guard sensitivity.fields.count <= 2, Set(sensitivity.fields).count == sensitivity.fields.count, sensitivity.fields.allSatisfy({ heatParameter(config, field: $0) != nil }), ["independentEndpointScenarios", "unknownDependenceEnvelope"].contains(sensitivity.relationship), sourceIsExplicit(sensitivity.source), sensitivity.source.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || sensitivity.source.reference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw ProjectDataError.contract("At most two sourced interval inputs; known correlated inputs require explicit separate scenarios") }
            for f in sensitivity.fields { guard heatParameter(config, field: f)?.bounds != nil else { throw ProjectDataError.contract("Sensitivity input has no declared bounds") } }
        }
    }
    public struct HeatParameterValue: Sendable {
        public let value: Double?
        public let source: SourceRecord?
        public let bounds: UncertaintyBounds?
        public let unit: String
    }
    public static func heatParameter(_ config: SteadyHeatBalanceConfiguration, field: String) -> HeatParameterValue? {
        func convert<Q>(_ p: PhysicalParameter<Q>) -> HeatParameterValue {
            if case .known(let v, let s, let b) = p { return .init(value: v, source: s, bounds: b, unit: Q.unit) }
            return .init(value: nil, source: nil, bounds: nil, unit: Q.unit)
        }
        switch field {
        case "conductance": return convert(config.conductance)
        case "indoorTemperature": return convert(config.indoorTemperature)
        case "outdoorTemperature": return convert(config.outdoorTemperature)
        case "outdoorAir": return convert(config.outdoorAir)
        case "infiltration": return convert(config.infiltration)
        case "density": return convert(config.density)
        case "specificHeat": return convert(config.specificHeat)
        case "internalSensibleHeat": return convert(config.internalSensibleHeat)
        case "solarSensibleHeat": return convert(config.solarSensibleHeat)
        default: return nil
        }
    }
    public static func heatMissing(_ config: SteadyHeatBalanceConfiguration) -> [AnalysisMissingReason] {
        var out: [AnalysisMissingReason] = []
        func missing(_ code: String, _ path: String, _ reason: String) { out.append(.init(code: code, fieldPath: path, reason: reason)) }
        for field in heatTerms + ["indoorTemperature", "outdoorTemperature", "density", "specificHeat"] where !config.excludedTerms.contains(field) {
            if heatParameter(config, field: field)?.value == nil { missing("heat_input_missing", field, "显热情景缺少 \(field)，未知不能补零。") }
        }
        if config.coverage?.indoorConditionConfirmed != true { missing("heat_condition_unconfirmed", "coverage", "明确采用室内温度作为估算条件；设定点不代表已达到室温。") }
        if config.coverage == nil { missing("heat_coverage_required", "coverage", "请声明UA、内部显热覆盖范围及空气参数适用条件与来源。") }
        if !config.excludedTerms.isEmpty && config.exclusions == nil { missing("heat_exclusion_reason", "exclusions", "每个排除项都需要明确理由；结果只能是指定项子集。") }
        if let sources = config.internalSources, !config.excludedTerms.contains("internalSensibleHeat") {
            if sources.contains(where: { $0.sensible.value == nil || $0.effectiveFraction.value == nil }) { missing("heat_source_unknown", "internalSources", "人员/设备清单含未知显热或有效比例。") }
            else if let total = config.internalSensibleHeat.value {
                let sum = sources.reduce(0.0) { $0 + ($1.sensible.value ?? 0) * ($1.effectiveFraction.value ?? 0) }
                if abs(sum - total) > max(1e-6, abs(total)*1e-9) { missing("heat_source_total", "internalSensibleHeat", "内部显热合计必须等于清单总显热×有效比例，不重复加对流/辐射/潜热。") }
            }
        }
        return out
    }
}
