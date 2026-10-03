import Foundation
import SimuCore

public struct PowerDraftSubtotal: Equatable, Sendable {
    public let payload: PowerEstimatePayload
    public let coveredMinutes: Int
    public let requestedMinutes: Int
    public let missingReasons: [AnalysisMissingReason]
    public var complete: Bool { missingReasons.isEmpty }
}
public enum PowerIntegrator {
    public static func splitAcrossMidnight(startMinute: Int, endMinute: Int) throws -> [AnalysisTimeWindow] {
        guard (0...1439).contains(startMinute), (0...1440).contains(endMinute), startMinute != endMinute else { throw ProjectDataError.contract("Invalid clock-time window") }
        if startMinute < endMinute { return [.init(startMinute: startMinute, endMinute: endMinute)] }
        return (endMinute > 0 ? [.init(startMinute: 0, endMinute: endMinute)] : []) + [.init(startMinute: startMinute, endMinute: 1440)]
    }
    /// A partial draft is never a successful complete numerical run.
    public static func draft(_ config: PowerEstimateConfiguration, deviceIDs: [UUID] = []) throws -> PowerDraftSubtotal {
        try ThermalEstimateValidation.validatePower(config)
        var segments: [PowerEstimateSegment] = [], subtotal = 0.0, lower = 0.0, upper = 0.0, covered = 0
        for w in config.requestedWindows {
            for interval in config.intervals where interval.endMinute > w.startMinute && interval.startMinute < w.endMinute {
                try Task.checkCancellation()
                guard case .known(let watts, _, let bounds) = interval.power else { continue }
                let start = max(w.startMinute, interval.startMinute), end = min(w.endMinute, interval.endMinute)
                let factor = Double(end-start)/60000
                let energy = watts * factor
                segments.append(.init(startMinute: start, endMinute: end, powerWatts: watts, energyKWh: energy, basis: interval.basis))
                subtotal += energy; lower += (bounds?.lower ?? watts)*factor; upper += (bounds?.upper ?? watts)*factor; covered += end-start
            }
        }
        guard [subtotal,lower,upper].allSatisfy(\.isFinite) else { throw ProjectDataError.contract("Power integral overflow") }
        let missing = ThermalEstimateValidation.powerMissing(config, deviceIDs: deviceIDs)
        return .init(payload: .init(timeBasis: config.timeBasis, requestedWindows: config.requestedWindows, segments: segments, totalEnergyKWh: missing.isEmpty ? subtotal : nil, knownSubtotalKWh: subtotal, lowerEnergyKWh: missing.isEmpty ? lower : nil, upperEnergyKWh: missing.isEmpty ? upper : nil), coveredMinutes: covered, requestedMinutes: config.requestedWindows.reduce(0){$0+$1.endMinute-$1.startMinute}, missingReasons: missing)
    }
    public static func integrate(_ config: PowerEstimateConfiguration, deviceIDs: [UUID] = []) throws -> PowerEstimatePayload {
        let draft = try draft(config, deviceIDs: deviceIDs)
        guard draft.complete else { throw ProjectDataError.contract("Incomplete power coverage: \(draft.missingReasons.map(\.code))") }
        return draft.payload
    }
    /// Only an explicitly accepted binary switch schedule is convertible.
    public static func intervalsFromSwitches(_ schedule: DailySchedule, power: ElectricalPower, basis: ElectricalPowerBasis, explicitlyAccepted: Bool) throws -> [AnalysisPowerInterval] {
        guard explicitlyAccepted, schedule.intervals.allSatisfy({ $0.fraction.value == 0 || $0.fraction.value == 1 }) else { throw ProjectDataError.contract("Schedule fraction is not compressor duty cycle") }
        return schedule.intervals.map { i in
            let adopted: ElectricalPower
            if i.fraction.value == 0 { adopted = .known(value: 0, source: .init(kind: .assumed, note: "User explicitly adopted a binary off interval")) } else { adopted = power }
            return .init(startMinute: i.startMinute, endMinute: i.endMinute, power: adopted, basis: basis)
        }
    }
}
public struct PowerEstimateExecutor: LocalAnalysisExecutor {
    public let method = AnalysisMethod(kind: .powerEstimate)
    public init() {}
    public func execute(_ request: LocalAnalysisRequest, progress: @escaping @Sendable (Double) async -> Void) async throws -> LocalAnalysisExecution {
        guard case .powerEstimate(let config) = request.resolvedInput.configuration.payload else { throw ProjectDataError.contract("Wrong power executor input") }
        await progress(0.1)
        let payload = try PowerIntegrator.integrate(config, deviceIDs: request.resolvedInput.snapshot.inputs.hvac.map(\.id))
        try Task.checkCancellation(); await progress(1)
        return .init(payload: .powerEstimate(payload), checks: .init(state: .passed))
    }
}
