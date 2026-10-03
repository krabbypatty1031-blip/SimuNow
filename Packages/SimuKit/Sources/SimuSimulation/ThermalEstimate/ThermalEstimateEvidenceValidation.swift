import Foundation
import SimuCore

/// Verify deterministic v1 calculations against their frozen adopted inputs.
/// Callers separately validate wire shape, request hashes and project ownership.
public enum ThermalEstimateEvidenceValidation {
    public static func validate(request: LocalAnalysisRequest, result: LocalAnalysisResult) throws {
        guard request.identity == result.identity, request.method == result.method, result.assumptions == request.resolvedInput.adoptedAssumptions else {
            throw ProjectDataError.contract("Thermal evidence identity/method mismatch")
        }
        guard request.method.kind != .airflowPreview else { return }
        guard request.method.methodVersion == 1 else {
            throw ProjectDataError.contract("Unsupported thermal evidence calculation version")
        }
        guard result.checks.state == .passed else { return }
        func rangeMatches(_ lower: Double?, _ upper: Double?, _ expectedLower: Double?, _ expectedUpper: Double?, required: Bool) -> Bool {
            // Legacy nominal-only records may omit newly added zero-width envelopes.
            if lower == nil && upper == nil { return !required }
            return lower == expectedLower && upper == expectedUpper
        }
        switch (request.resolvedInput.configuration.payload, result.payload) {
        case (.powerEstimate(let configuration), .powerEstimate(let actual)):
            let expected = try PowerIntegrator.integrate(configuration, deviceIDs: request.resolvedInput.snapshot.inputs.hvac.map(\.id))
            let adoptsBounds = configuration.intervals.contains { interval in
                guard configuration.requestedWindows.contains(where: { interval.endMinute > $0.startMinute && interval.startMinute < $0.endMinute }), case .known(_, _, let bounds) = interval.power else { return false }
                return bounds != nil
            }
            guard actual.timeBasis == expected.timeBasis, actual.requestedWindows == expected.requestedWindows,
                  actual.segments == expected.segments, actual.totalEnergyKWh == expected.totalEnergyKWh,
                  actual.knownSubtotalKWh == expected.knownSubtotalKWh,
                  rangeMatches(actual.lowerEnergyKWh, actual.upperEnergyKWh, expected.lowerEnergyKWh, expected.upperEnergyKWh, required: adoptsBounds) else {
                throw ProjectDataError.contract("Power evidence differs from the frozen v1 intervals/integral/envelope")
            }
        case (.steadyHeatBalance(let configuration), .steadyHeatBalance(let actual)):
            let expected = try SteadyHeatBalance.calculate(configuration)
            guard Set(actual.terms.map(\.id)).count == actual.terms.count else {
                throw ProjectDataError.contract("Repeated thermal evidence ledger term")
            }
            let actualLedger = Dictionary(uniqueKeysWithValues: actual.terms.map { ($0.id, $0.signedWatts) })
            let expectedLedger = Dictionary(uniqueKeysWithValues: expected.terms.map { ($0.id, $0.signedWatts) })
            let adoptsBounds = !(configuration.sensitivity?.fields.isEmpty ?? true)
            guard actualLedger == expectedLedger, actual.totalSignedWatts == expected.totalSignedWatts,
                  actual.coolingSensibleWatts == expected.coolingSensibleWatts,
                  actual.excludedTerms == expected.excludedTerms, actual.completeness == expected.completeness,
                  actual.capacityScreen == expected.capacityScreen,
                  actual.adoptedSensibleCapacityWatts == expected.adoptedSensibleCapacityWatts,
                  rangeMatches(actual.lowerCoolingSensibleWatts, actual.upperCoolingSensibleWatts, expected.lowerCoolingSensibleWatts, expected.upperCoolingSensibleWatts, required: adoptsBounds),
                  actual.scenarios == expected.scenarios || actual.scenarios == nil && !adoptsBounds,
                  actual.notes == nil || actual.notes == expected.notes else {
                throw ProjectDataError.contract("Heat evidence differs from the frozen v1 ledger/envelope/capacity/scenarios")
            }
        default: throw ProjectDataError.contract("Thermal evidence payload/configuration mismatch")
        }
    }
}
