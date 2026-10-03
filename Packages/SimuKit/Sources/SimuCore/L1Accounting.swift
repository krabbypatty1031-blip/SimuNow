import Foundation

/// Representative-day inputs. Weather is a package-relative path, never a home directory.
public struct L1DayContext: Equatable, Sendable {
    public var weatherPath: String?
    public var weatherHash: String?
    /// Cooling already computed by EnergyPlus or a fixture. Never invent a lumped UA load.
    public var coolingLoadW: Double?
    public var scheduleHash: String?
    /// Occupied-day mean window heat into the zone (W). Nil means not reported.
    public var windowHeatW: Double?
    /// Occupied-day mean opaque inside-face conduction into the zone (W).
    public var opaqueHeatW: Double?

    public init(
        weatherPath: String? = nil,
        weatherHash: String? = nil,
        coolingLoadW: Double? = nil,
        scheduleHash: String? = nil,
        windowHeatW: Double? = nil,
        opaqueHeatW: Double? = nil
    ) {
        self.weatherPath = weatherPath
        self.weatherHash = weatherHash
        self.coolingLoadW = coolingLoadW
        self.scheduleHash = scheduleHash
        self.windowHeatW = windowHeatW
        self.opaqueHeatW = opaqueHeatW
    }
}

public enum L1AccountingError: Error, Equatable, Sendable {
    case incompleteProject
}

/// L1 accounting only. Does not run EnergyPlus or invent envelope watts.
public enum L1Accounting {
    public static let representativeDay = ResultPeriod(kind: "representative_day", start: "07-15", end: "07-15")

    /// Period follows the draft typical-year day. Missing weather stays 15 July.
    public static func representativeDay(for draft: ProjectDraft) -> ResultPeriod {
        let stamp = draft.resolvedWeather.mmdd
        return ResultPeriod(kind: "representative_day", start: stamp, end: stamp)
    }

    public static func evaluate(
        identity: RunIdentity,
        draft: ProjectDraft,
        context: L1DayContext
    ) throws -> SimulationResult {
        guard draft.hasCompletePhysicalModel, let hvac = draft.hvac else {
            throw L1AccountingError.incompleteProject
        }
        if let weatherPath = context.weatherPath {
            guard InputSnapshotHash.isSafeSnapshotPath(weatherPath) else {
                throw TaskProtocolError.unsafeSnapshotPath
            }
        }
        let scheduleDigest = scheduleHash(of: draft)
        if let declared = context.scheduleHash, declared != scheduleDigest {
            throw TaskProtocolError.hashMismatch
        }

        let hasWeather = context.weatherPath != nil
        let cooling = hasWeather ? context.coolingLoadW : nil
        let cop = hvac.cop.value
        let electricity: Double?
        if let cooling, cop > 0 {
            electricity = cooling / cop
        } else {
            electricity = nil
        }

        // Missing weather or cooling stays omitted. A zero watt is not an unknown load.
        let omitLoads = cooling == nil || electricity == nil
        let omitWindow = context.windowHeatW == nil
        let omitOpaque = context.opaqueHeatW == nil
        let metrics = [
            ResultMetric(
                name: "q_cool_w",
                value: omitLoads ? nil : cooling,
                unit: "W",
                method: "equivalent_ideal_loads",
                fidelity: .l1,
                omitted: omitLoads
            ),
            ResultMetric(
                name: "p_elec_w",
                value: omitLoads ? nil : electricity,
                unit: "W",
                method: "equivalent_ideal_loads",
                fidelity: .l1,
                omitted: omitLoads
            ),
            ResultMetric(
                name: "annual_kwh",
                value: nil,
                unit: "kWh",
                method: "not_modeled",
                fidelity: .l1,
                omitted: true
            ),
            ResultMetric(
                name: "window_heat_w",
                value: omitWindow ? nil : context.windowHeatW,
                unit: "W",
                method: "energyplus_window_heat",
                fidelity: .l1,
                omitted: omitWindow,
                reason: omitWindow ? "EnergyPlus did not report window heat for this run" : nil
            ),
            ResultMetric(
                name: "opaque_heat_w",
                value: omitOpaque ? nil : context.opaqueHeatW,
                unit: "W",
                method: "energyplus_opaque_conduction",
                fidelity: .l1,
                omitted: omitOpaque,
                reason: omitOpaque ? "EnergyPlus did not report opaque conduction for this run" : nil
            )
        ]

        return SimulationResult(
            identity: identity,
            state: .succeeded,
            quality: .notEvaluated,
            metrics: metrics,
            period: representativeDay(for: draft),
            weatherPath: context.weatherPath,
            weatherHash: hasWeather ? context.weatherHash : nil,
            supplyTemperatureC: hvac.supplyTemperatureC.value,
            setpointC: hvac.setpointC.value,
            schedule: draft.occupancy?.schedule.map { ResultPeriod(kind: $0.kind, start: $0.start, end: $0.end) },
            hvacSchedule: hvac.schedule.map { ResultPeriod(kind: $0.kind, start: $0.start, end: $0.end) },
            scheduleHash: scheduleDigest
        )
    }

    /// Hash only the occupied-hour objects so weather file bytes cannot stand in for a schedule.
    public static func scheduleHash(of draft: ProjectDraft) -> String? {
        guard draft.occupancy?.schedule != nil || draft.hvac?.schedule != nil else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        struct Wire: Encodable {
            var occupancy: OccupiedHours?
            var hvac: OccupiedHours?
            enum CodingKeys: String, CodingKey { case occupancy, hvac }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(occupancy, forKey: .occupancy)
                try container.encodeIfPresent(hvac, forKey: .hvac)
            }
        }
        guard let data = try? encoder.encode(Wire(occupancy: draft.occupancy?.schedule, hvac: draft.hvac?.schedule)) else {
            return nil
        }
        return InputSnapshotHash.sha256Hex(data)
    }
}
