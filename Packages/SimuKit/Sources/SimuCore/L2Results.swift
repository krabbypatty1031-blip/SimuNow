import Foundation

/// L2 position-level sample at one seat. Values come only from a
/// quality-passed field; a failed field omits seats instead of filling 0.
public struct SeatSample: Codable, Equatable, Sendable {
    public var id: String
    /// Contract frame: metre, right-handed, Z-up, seat head height.
    public var x: Double
    public var y: Double
    public var z: Double
    /// Air temperature at the seat, degrees Celsius.
    public var tC: Double
    /// Air speed magnitude at the seat, m/s.
    public var uMag: Double
    /// Near-zero speeds carry absolute error, not a huge percent error.
    public var lowSpeedAbsoluteError: Bool?
    /// ISO 7730 PMV at the seat; present only when comfort inputs were
    /// complete and in range. Never filled with 0 when not evaluated.
    public var pmv: Double?
    /// ISO 7730 PPD [%] at the seat; present only when pmv is present.
    public var ppd: Double?

    public init(
        id: String,
        x: Double,
        y: Double,
        z: Double,
        tC: Double,
        uMag: Double,
        lowSpeedAbsoluteError: Bool? = nil,
        pmv: Double? = nil,
        ppd: Double? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.z = z
        self.tC = tC
        self.uMag = uMag
        self.lowSpeedAbsoluteError = lowSpeedAbsoluteError
        self.pmv = pmv
        self.ppd = ppd
    }
}

/// Numerical quality gates for one L2 field. Every value is optional because
/// a missing or partial log is evidence of nothing; `allGatesPass` mirrors
/// the worker's `quality_pass`: missing logs never pass, and a missing gate
/// is not a zero error.
public struct QualityDetail: Codable, Equatable, Sendable {
    public var checkMesh: String?
    public var solverEnded: Bool?
    public var monitorsStable: Bool?
    public var massRelativeError: Double?
    public var massGate: Double?
    public var energyRelativeError: Double?
    public var energyGate: Double?

    public init(
        checkMesh: String? = nil,
        solverEnded: Bool? = nil,
        monitorsStable: Bool? = nil,
        massRelativeError: Double? = nil,
        massGate: Double? = nil,
        energyRelativeError: Double? = nil,
        energyGate: Double? = nil
    ) {
        self.checkMesh = checkMesh
        self.solverEnded = solverEnded
        self.monitorsStable = monitorsStable
        self.massRelativeError = massRelativeError
        self.massGate = massGate
        self.energyRelativeError = energyRelativeError
        self.energyGate = energyGate
    }

    /// Every gate must hold; any missing side fails rather than passing by
    /// omission. Relative errors must sit strictly under their gates.
    public var allGatesPass: Bool {
        guard checkMesh == "ok", solverEnded == true, monitorsStable == true else {
            return false
        }
        func underGate(_ error: Double?, _ gate: Double?) -> Bool {
            guard let error, let gate else { return false }
            return error < gate
        }
        return underGate(massRelativeError, massGate) && underGate(energyRelativeError, energyGate)
    }
}
